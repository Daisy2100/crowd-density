# 群眾密度監控 - 後端 API

**Vision Layer** - FastAPI + YOLOv8n

## 🎯 功能特點

- ✅ **即時人群偵測**: 使用 YOLOv8n 輕量級模型
- ✅ **密度計算**: 支援自訂區域面積與門檻
- ✅ **ROI 區域**: 支援百分比裁切特定監控區域
- ✅ **結構化輸出**: JSON 格式，易於整合 n8n/前端
- ✅ **CORS 支援**: 允許跨域請求

## 🚀 快速啟動

### 1. 安裝依賴

```powershell
# 建立虛擬環境 (建議)
python -m venv venv
.\venv\Scripts\Activate.ps1

# 安裝套件
pip install -r requirements.txt
```

### 2. 啟動服務

```powershell
# 開發模式 (自動重載)
python main.py

# 或使用 uvicorn
uvicorn main:app --host 0.0.0.0 --port 8001 --reload
```

服務將在 **http://localhost:8001** 啟動

### 3. 查看 API 文件

- Swagger UI: http://localhost:8001/docs
- ReDoc: http://localhost:8001/redoc

## 📡 API 端點

### `GET /health`
健康檢查

**回應範例:**
```json
{
  "status": "healthy",
  "model_loaded": true,
  "service": "Crowd Density Detection API",
  "version": "1.0.0"
}
```

### `POST /api/detect`
群眾密度偵測

**請求參數:**
- `file` (required): 圖片檔案 (jpg/jpeg/png)
- `roi_area_m2` (optional, default=20.0): 監控區域面積 (㎡)
- `density_warn` (optional, default=5.0): 警告門檻 (人/㎡)
- `density_danger` (optional, default=6.5): 危險門檻 (人/㎡)
- `roi_x0`, `roi_y0`, `roi_x1`, `roi_y1` (optional): ROI 百分比座標
- `conf_threshold` (optional, default=0.5): 偵測信心度門檻

**回應範例:**
```json
{
  "person_count": 8,
  "density": 0.4,
  "status": "normal",
  "bounding_boxes": [
    {
      "x1": 120,
      "y1": 45,
      "x2": 180,
      "y2": 220,
      "confidence": 0.89
    }
  ],
  "image_width": 1280,
  "image_height": 720,
  "roi_area_m2": 20.0,
  "density_warn_threshold": 5.0,
  "density_danger_threshold": 6.5,
  "message": "✅ 正常。當前密度 0.40 人/㎡"
}
```

**狀態值:**
- `normal`: 密度低於警告門檻
- `warning`: 密度介於警告與危險門檻之間
- `danger`: 密度超過危險門檻

## 🧪 測試範例

### PowerShell (Windows)

```powershell
# 測試圖片偵測
$image = Get-Item "test.jpg"
$uri = "http://localhost:8001/api/detect"

$form = @{
    file = $image
    roi_area_m2 = "20"
    density_warn = "5.0"
    density_danger = "6.5"
}

Invoke-RestMethod -Uri $uri -Method Post -Form $form
```

### Python

```python
import requests

url = "http://localhost:8001/api/detect"

with open("test.jpg", "rb") as f:
    files = {"file": f}
    data = {
        "roi_area_m2": 20.0,
        "density_warn": 5.0,
        "density_danger": 6.5
    }
    response = requests.post(url, files=files, data=data)
    print(response.json())
```

### curl

```bash
curl -X POST "http://localhost:8001/api/detect" \
  -F "file=@test.jpg" \
  -F "roi_area_m2=20" \
  -F "density_warn=5.0" \
  -F "density_danger=6.5"
```

## 🐳 Docker 部署

```powershell
# 建置映像
docker build -t crowd-density-backend .

# 執行容器
docker run -d -p 8001:8001 --name crowd-backend crowd-density-backend
```

## 📊 與其他服務整合

### 前端 (Vue 3)
前端每 2000ms 呼叫此 API，參考 `frontend/src/App.vue`

### n8n 自動化
n8n 可定期呼叫此 API，並根據 `status` 欄位觸發警報流程

## 🔧 技術規格

| 項目 | 配置 |
|------|------|
| 框架 | FastAPI |
| AI 模型 | YOLOv8n |
| 內部 Port | 8001 |
| 偵測類別 | Person (COCO class 0) |
| 推論速度 | ~50-100ms (CPU, e2-medium) |

## 📝 注意事項

1. **首次啟動**: 會自動下載 YOLOv8n 模型 (~6MB)
2. **記憶體需求**: 建議至少 2GB RAM
3. **CPU 優化**: YOLOv8n 針對 CPU 推論優化
4. **生產環境**: 請修改 CORS 設定，限制允許的來源

## 🆘 常見問題

### Q: 模型載入失敗？
A: 確保 `yolov8n.pt` 在同目錄，或讓程式自動下載

### Q: 偵測速度慢？
A: 調低圖片解析度或使用 GPU 版本

### Q: CORS 錯誤？
A: 檢查 `main.py` 的 `allow_origins` 設定

## 📖 相關文件

- [FastAPI 官方文件](https://fastapi.tiangolo.com/)
- [Ultralytics YOLOv8](https://docs.ultralytics.com/)
- [專案總覽](../README.md)
