<#
  publish.ps1 —— 一条命令把本目录发布成 GitHub 仓库
  用法：
    .\publish.ps1 -Token ghp_xxxxxxxx -RepoName Pojia-Ultimate
    可选：-Private  建私有仓库（默认公开）
          -User     指定账号（默认取 token 所属账号）
  说明：Token 至少需要 repo 权限（classic）或 Contents+Administration:Write（fine-grained）
#>

param(
  [string]$Token,
  [string]$RepoName = "Pojia-Ultimate",
  [string]$User,
  [string]$Description = "破甲 Pojia | 国产无审查大模型 · 全量破甲版 · OpenAI 兼容中转 | hunmeng.icu",
  [switch]$Private
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

if (-not $Token) {
  $sec = Read-Host "粘贴 GitHub Token（输入不回显）" -AsSecureString
  $Token = [System.Net.NetworkCredential]::new("", $sec).Password
}
if (-not $Token) { throw "没有 Token，无法发布。" }

$headers = @{
  Authorization          = "Bearer $Token"
  "User-Agent"           = "pojia-publish-script"
  Accept                 = "application/vnd.github+json"
  "X-GitHub-Api-Version" = "2022-11-28"
}

# 1) 确认身份
if (-not $User) {
  Write-Host "[1/5] 校验 Token..." -ForegroundColor Cyan
  $me = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -Method Get
  $User = $me.login
}
Write-Host "    账号: $User" -ForegroundColor Green

# 2) 创建仓库（已存在则跳过）
Write-Host "[2/5] 创建仓库 $User/$RepoName ..." -ForegroundColor Cyan
$body = @{
  name        = $RepoName
  description = $Description
  private     = [bool]$Private
  has_issues  = $true
  has_wiki    = $false
  auto_init   = $false
} | ConvertTo-Json -Depth 5

try {
  $repo = Invoke-RestMethod -Uri "https://api.github.com/user/repos" -Headers $headers -Method Post -Body $body -ContentType "application/json"
  Write-Host "    已创建: $($repo.html_url)" -ForegroundColor Green
} catch {
  $code = $_.Exception.Response.StatusCode.value__
  if ($code -eq 422) {
    Write-Host "    仓库已存在，直接推送。" -ForegroundColor Yellow
    $repo = Invoke-RestMethod -Uri "https://api.github.com/repos/$User/$RepoName" -Headers $headers -Method Get
  } else { throw }

  # 强制公开/私有时，同步可见性
  $patch = @{ private = [bool]$Private } | ConvertTo-Json
  try { Invoke-RestMethod -Uri "https://api.github.com/repos/$User/$RepoName" -Headers $headers -Method Patch -Body $patch -ContentType "application/json" | Out-Null } catch {}
}

# 3) 本地提交
Write-Host "[3/5] 初始化并提交..." -ForegroundColor Cyan
if (-not (Test-Path ".git")) { git init | Out-Null }
git checkout -B main 2>$null | Out-Null
git add -A
$hasChanges = git status --porcelain
if ($hasChanges) {
  git -c user.name="$User" -c user.email="$User@users.noreply.github.com" commit -m "docs: 破甲 Pojia 中转站介绍与全平台文案" | Out-Null
  Write-Host "    已提交改动" -ForegroundColor Green
} else {
  Write-Host "    无新改动，跳过提交" -ForegroundColor Yellow
}

# 4) 推送
Write-Host "[4/5] 推送到 GitHub..." -ForegroundColor Cyan
git remote remove origin 2>$null
git remote add origin "https://x-access-token:$Token@github.com/$User/$RepoName.git"
git push -u origin main --force

# 5) 清理 token 痕迹
Write-Host "[5/5] 清理凭据..." -ForegroundColor Cyan
git remote set-url origin "https://github.com/$User/$RepoName.git"
Write-Host ""
Write-Host "完成 → https://github.com/$User/$RepoName" -ForegroundColor Green

# 可选：打 topics 让仓库更容易被搜到
$topics = @("llm","uncensored","openai-compatible","api-relay","chinese-llm","pojia","无审查模型","大模型api")
$tBody = @{ names = $topics } | ConvertTo-Json
try { Invoke-RestMethod -Uri "https://api.github.com/repos/$User/$RepoName/topics" -Headers $headers -Method Put -Body $tBody -ContentType "application/json" | Out-Null; Write-Host "已设置 Topics" -ForegroundColor Green } catch {}
