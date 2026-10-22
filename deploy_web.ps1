# deploy_web.ps1
# Automated web deployment script for ConstructIQ to GitHub Pages
# Builds the Flutter web release, removes oversized ONNX models from build output, and publishes to gh-pages

$ErrorActionPreference = "Stop"

Write-Host "==> [1/5] Building Flutter Web..." -ForegroundColor Cyan
Set-Location "$PSScriptRoot\construction_flutter_app"
flutter build web --release --base-href "/ConstructIQ/"

$webOutputDir = "$PSScriptRoot\construction_flutter_app\build\web"
Set-Location $webOutputDir

Write-Host "==> [2/5] Purging oversized ONNX ML models from build output..." -ForegroundColor Yellow
# Delete models directly from web output directory so they are not packaged or deployed
$onnxDir = Join-Path $webOutputDir "assets\assets\models"
if (Test-Path "$onnxDir\best.onnx") {
    Remove-Item "$onnxDir\best.onnx" -Force -Verbose
    Write-Host "Removed best.onnx (104MB) from build/web" -ForegroundColor Green
}
if (Test-Path "$onnxDir\cost_overrun_model.onnx") {
    Remove-Item "$onnxDir\cost_overrun_model.onnx" -Force -Verbose
    Write-Host "Removed cost_overrun_model.onnx from build/web" -ForegroundColor Green
}

# Update AssetManifest.json so Flutter Web does not expect the deleted ONNX files
$manifestFiles = @("assets\AssetManifest.json", "assets\AssetManifest.bin.json")
foreach ($mFile in $manifestFiles) {
    $mPath = Join-Path $webOutputDir $mFile
    if (Test-Path $mPath) {
        $content = Get-Content $mPath -Raw
        $content = $content -replace '"assets/models/best.onnx":\[[^\]]*\],?', ''
        $content = $content -replace '"assets/models/cost_overrun_model.onnx":\[[^\]]*\],?', ''
        $content = $content -replace ',\s*}', '}'
        Set-Content -Path $mPath -Value $content -NoNewline
        Write-Host "Cleaned AssetManifest in $mFile" -ForegroundColor Green
    }
}

# Ensure .gitignore in build output ignores any leftover model files
Add-Content .gitignore "`nassets/assets/models/best.onnx`nassets/assets/models/cost_overrun_model.onnx`n*.onnx"

# Reset local git history in build folder so past commits containing large models are completely erased
if (Test-Path ".git") {
    Remove-Item -Recurse -Force ".git" -ErrorAction SilentlyContinue
}
git init
git checkout -B gh-pages
git remote add origin "https://github.com/Sukhshum2628/ConstructIQ.git"

Write-Host "==> [4/5] Committing web assets..." -ForegroundColor Cyan
git add -A
git commit -m "deploy: flutter web build (ML models excluded for GitHub Pages)"

Write-Host "==> [5/5] Pushing to gh-pages branch..." -ForegroundColor Cyan
git push --force origin gh-pages

Set-Location "$PSScriptRoot"
Write-Host "Deployment Complete! Site will be updated at: https://Sukhshum2628.github.io/ConstructIQ" -ForegroundColor Green
