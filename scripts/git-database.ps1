# =============================
# GitCloud Push Script
# Push all files from C:\Windows\database › GitHub branch "templates"
# =============================

$SourceDir  = "C:\Windows\database"
$WorkDir    = "C:\Temp\gitcloud_push"
$RepoUrl    = "https://github.com/pauliukovich/gitcloud.pl.git"
$BranchName = "templates"

# Create work folder
if (Test-Path $WorkDir) {
    Remove-Item $WorkDir -Recurse -Force
}
New-Item -ItemType Directory -Path $WorkDir | Out-Null

Write-Host "Copying database files..." -ForegroundColor Cyan
Copy-Item -Path "$SourceDir\*" -Destination $WorkDir -Recurse -Force

# Check if GitHub CLI installed
if (-not (Get-Command gh.exe -ErrorAction SilentlyContinue)) {
    Write-Host "GitHub CLI (gh) not installed. Install from https://cli.github.com/" -ForegroundColor Red
    exit
}

# Auth if needed
Write-Host "Authenticating with GitHub..." -ForegroundColor Yellow
gh auth status 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Running GitHub login..." -ForegroundColor Yellow
    gh auth login
}

# Initialize repository
Set-Location $WorkDir

if (-not (Test-Path ".git")) {
    git init
    git remote add origin $RepoUrl
}

# Checkout correct branch
git fetch origin
git checkout -B $BranchName

# Stage and commit
git add .

$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
git commit -m "Automated push of database files ($now)" 2>$null

# Push
Write-Host "Pushing to GitHub..." -ForegroundColor Green
git push -u origin $BranchName --force

Write-Host "Done! Files pushed to GitHub branch '$BranchName'." -ForegroundColor Cyan
