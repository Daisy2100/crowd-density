# 群眾密度監控 - 後端啟動腳本
# 自動啟動虛擬環境並執行 FastAPI 服務

Write-Host "🚀 啟動群眾密度監控後端..." -ForegroundColor Cyan
Write-Host ""

# 檢查虛擬環境
if (Test-Path ".\venv\Scripts\Activate.ps1") {
    Write-Host "✅ 找到虛擬環境，正在啟動..." -ForegroundColor Green
    & .\venv\Scripts\Activate.ps1
} else {
    Write-Host "⚠️  未找到虛擬環境，使用系統 Python" -ForegroundColor Yellow
    Write-Host "建議執行: python -m venv venv" -ForegroundColor Yellow
    Write-Host ""
}

# 檢查依賴
Write-Host "📦 檢查依賴套件..." -ForegroundColor Cyan
$requiredPackages = @("fastapi", "uvicorn", "ultralytics")
$missingPackages = @()

foreach ($package in $requiredPackages) {
    $installed = pip show $package 2>$null
    if (-not $installed) {
        $missingPackages += $package
    }
}

if ($missingPackages.Count -gt 0) {
    Write-Host "⚠️  缺少依賴: $($missingPackages -join ', ')" -ForegroundColor Yellow
    $install = Read-Host "是否安裝缺少的套件? (y/N)"
    if ($install -eq 'y' -or $install -eq 'Y') {
        Write-Host "📥 安裝依賴套件..." -ForegroundColor Cyan
        pip install -r requirements.txt
    } else {
        Write-Host "❌ 取消啟動" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "🎯 啟動 FastAPI 服務 (Port 8001)..." -ForegroundColor Green
Write-Host "📡 API 文件: http://localhost:8001/docs" -ForegroundColor Cyan
Write-Host "🏥 健康檢查: http://localhost:8001/health" -ForegroundColor Cyan
Write-Host ""
Write-Host "按 Ctrl+C 停止服務" -ForegroundColor Yellow
Write-Host "=" * 60
Write-Host ""

# 啟動服務
python main.py
