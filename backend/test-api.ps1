# API 測試腳本
# 測試群眾密度監控後端 API

Write-Host "🧪 測試群眾密度監控 API" -ForegroundColor Cyan
Write-Host "=" * 60
Write-Host ""

$apiBase = "http://localhost:8001"

# 測試 1: 健康檢查
Write-Host "1️⃣  測試健康檢查端點..." -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "$apiBase/health" -Method Get
    Write-Host "✅ 健康檢查成功" -ForegroundColor Green
    Write-Host "   狀態: $($health.status)" -ForegroundColor Gray
    Write-Host "   模型載入: $($health.model_loaded)" -ForegroundColor Gray
    Write-Host "   服務: $($health.service)" -ForegroundColor Gray
} catch {
    Write-Host "❌ 健康檢查失敗" -ForegroundColor Red
    Write-Host "   錯誤: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "⚠️  請確認後端服務是否正在運行:" -ForegroundColor Yellow
    Write-Host "   1. cd backend" -ForegroundColor Cyan
    Write-Host "   2. python main.py" -ForegroundColor Cyan
    exit 1
}

Write-Host ""

# 測試 2: 根端點
Write-Host "2️⃣  測試根端點..." -ForegroundColor Yellow
try {
    $root = Invoke-RestMethod -Uri "$apiBase/" -Method Get
    Write-Host "✅ 根端點回應成功" -ForegroundColor Green
    Write-Host "   版本: $($root.version)" -ForegroundColor Gray
    Write-Host "   後端: $($root.tech_stack.backend)" -ForegroundColor Gray
    Write-Host "   模型: $($root.tech_stack.model)" -ForegroundColor Gray
} catch {
    Write-Host "❌ 根端點測試失敗" -ForegroundColor Red
}

Write-Host ""

# 測試 3: 偵測端點 (需要圖片)
Write-Host "3️⃣  測試偵測端點..." -ForegroundColor Yellow

# 檢查是否有測試圖片
$testImages = Get-ChildItem -Path "." -Filter "*.jpg" -ErrorAction SilentlyContinue
if (-not $testImages) {
    $testImages = Get-ChildItem -Path "." -Filter "*.png" -ErrorAction SilentlyContinue
}

if ($testImages) {
    $testImage = $testImages[0]
    Write-Host "   使用測試圖片: $($testImage.Name)" -ForegroundColor Gray
    
    try {
        $form = @{
            file = Get-Item $testImage.FullName
            roi_area_m2 = "20"
            density_warn = "5.0"
            density_danger = "6.5"
        }
        
        $result = Invoke-RestMethod -Uri "$apiBase/api/detect" -Method Post -Form $form
        
        Write-Host "✅ 偵測成功" -ForegroundColor Green
        Write-Host "   人數: $($result.person_count)" -ForegroundColor Gray
        Write-Host "   密度: $($result.density) 人/㎡" -ForegroundColor Gray
        Write-Host "   狀態: $($result.status)" -ForegroundColor Gray
        Write-Host "   訊息: $($result.message)" -ForegroundColor Gray
        Write-Host "   偵測到 $($result.bounding_boxes.Count) 個邊界框" -ForegroundColor Gray
    } catch {
        Write-Host "❌ 偵測失敗" -ForegroundColor Red
        Write-Host "   錯誤: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "⚠️  未找到測試圖片 (*.jpg 或 *.png)" -ForegroundColor Yellow
    Write-Host "   跳過偵測端點測試" -ForegroundColor Gray
    Write-Host ""
    Write-Host "💡 提示: 可以在 backend 目錄放置測試圖片來測試偵測功能" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "=" * 60
Write-Host "✅ API 測試完成" -ForegroundColor Green
Write-Host ""
Write-Host "📖 完整 API 文件: $apiBase/docs" -ForegroundColor Cyan
Write-Host ""
