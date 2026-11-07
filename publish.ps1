param(
  [string]$Token,
  [string]$RepoName = "Pojia-Ultimate",
  [string]$User,
  [string]$Description = "Pojia | uncensored Chinese LLM relay (OpenAI compatible)",
  [switch]$Private
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

if (-not $Token) {
  $sec = Read-Host "GitHub Token (input hidden)" -AsSecureString
  $Token = [System.Net.NetworkCredential]::new("", $sec).Password
}
if (-not $Token) { throw "No token supplied." }

$headers = @{
  Authorization          = "Bearer $Token"
  "User-Agent"           = "pojia-publish-script"
  Accept                 = "application/vnd.github+json"
  "X-GitHub-Api-Version" = "2022-11-28"
}

# step 1 - identify account
if (-not $User) {
  Write-Host "[1/5] validating token ..." -ForegroundColor Cyan
  $me = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -Method Get
  $User = $me.login
}
Write-Host "      account: $User" -ForegroundColor Green

# step 2 - create repo (tolerate already existing)
Write-Host "[2/5] creating repo $User/$RepoName ..." -ForegroundColor Cyan
$body = @{
  name        = $RepoName
  description = $Description
  private     = [bool]$Private
  has_issues  = $true
  has_wiki    = $false
  auto_init   = $false
} | ConvertTo-Json -Depth 5

$created = $true
try {
  $repo = Invoke-RestMethod -Uri "https://api.github.com/user/repos" -Headers $headers -Method Post -Body $body -ContentType "application/json"
  Write-Host "      created: $($repo.html_url)" -ForegroundColor Green
}
catch {
  $code = $_.Exception.Response.StatusCode.value__
  if ($code -ne 422) { throw }
  $created = $false
  Write-Host "      repo already exists, pushing to it" -ForegroundColor Yellow
  $repo = Invoke-RestMethod -Uri "https://api.github.com/repos/$User/$RepoName" -Headers $headers -Method Get
}

if (-not $created) {
  $patch = @{ private = [bool]$Private } | ConvertTo-Json
  Invoke-RestMethod -Uri "https://api.github.com/repos/$User/$RepoName" -Headers $headers -Method Patch -Body $patch -ContentType "application/json" | Out-Null
}

# step 3 - local commit
Write-Host "[3/5] git init + commit ..." -ForegroundColor Cyan
if (-not (Test-Path ".git")) { git init | Out-Null }
git checkout -B main 2>$null | Out-Null
git add -A
$pending = git status --porcelain
if ($pending) {
  git -c user.name="$User" -c user.email="$User@users.noreply.github.com" commit -m "docs: Pojia relay intro and promo copy" | Out-Null
  Write-Host "      committed" -ForegroundColor Green
}
else {
  Write-Host "      nothing to commit" -ForegroundColor Yellow
}

# step 4 - push
Write-Host "[4/5] pushing ..." -ForegroundColor Cyan
git remote remove origin 2>$null
git remote add origin "https://x-access-token:$Token@github.com/$User/$RepoName.git"
git push -u origin main --force

# step 5 - scrub token from remote config
Write-Host "[5/5] scrubbing credentials ..." -ForegroundColor Cyan
git remote set-url origin "https://github.com/$User/$RepoName.git"

Write-Host ""
Write-Host "DONE -> https://github.com/$User/$RepoName" -ForegroundColor Green

$topics = @("llm", "uncensored", "openai-compatible", "api-relay", "chinese-llm", "pojia")
$tBody = @{ names = $topics } | ConvertTo-Json
Invoke-RestMethod -Uri "https://api.github.com/repos/$User/$RepoName/topics" -Headers $headers -Method Put -Body $tBody -ContentType "application/json" | Out-Null
Write-Host "topics set" -ForegroundColor Green
