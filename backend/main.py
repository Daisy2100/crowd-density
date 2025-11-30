"""
群眾密度監控 FastAPI 後端
Vision Layer - 使用 YOLOv8n 進行人群偵測與密度計算
內部 Port: 8001

優化重點:
1. ONNX 模型載入 (降低記憶體佔用)
2. 主動記憶體管理 (gc.collect)
3. 圖片尺寸限制 (防止 OOM)
4. 推論參數優化 (imgsz=640)
"""

from fastapi import FastAPI, File, UploadFile, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from ultralytics import YOLO
from PIL import Image
import cv2
import numpy as np
import io
import gc  # 記憶體管理
import torch  # PyTorch 用於修復載入問題
from typing import List, Dict, Optional
from pydantic import BaseModel
import logging
from contextlib import asynccontextmanager
import httpx  # 用於發送 webhook 到 n8n
import os
from datetime import datetime
from dotenv import load_dotenv

# 載入環境變數
load_dotenv()

# 設定日誌
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# 全域模型變數
model = None

# n8n Webhook 配置
N8N_WEBHOOK_URL = os.getenv("N8N_WEBHOOK_URL", "http://n8n:5678/webhook/crowd-alert")
ENABLE_N8N_ALERTS = os.getenv("ENABLE_N8N_ALERTS", "true").lower() == "true"

# 警報節流配置 (避免頻繁發送)
last_alert_time = None
ALERT_COOLDOWN_SECONDS = int(os.getenv("ALERT_COOLDOWN_SECONDS", "60"))

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    應用生命週期管理 (取代舊的 on_event)
    啟動時載入模型, 關閉時清理資源
    """
    global model
    # 啟動階段
    try:
        logger.info("載入 YOLOv8n 模型...")
        
        import os
        onnx_path = "yolov8n.onnx"
        pt_path = "yolov8n.pt"
        
        if os.path.exists(onnx_path):
            logger.info("🚀 使用 ONNX 模型 (記憶體優化)")
            model = YOLO(onnx_path, task='detect')
        elif os.path.exists(pt_path):
            logger.info("📦 使用 PyTorch 模型 (修復 PyTorch 2.6+ 載入問題)")
            
            # 修復 PyTorch 2.6+ weights_only 預設值問題
            # 使用 weights_only=False (信任 YOLOv8n 官方模型)
            original_load = torch.load
            torch.load = lambda *args, **kwargs: original_load(
                *args, **{**kwargs, 'weights_only': False}
            )
            
            try:
                model = YOLO(pt_path)
            finally:
                torch.load = original_load  # 恢復原始函數
        else:
            raise FileNotFoundError("找不到模型檔案 (yolov8n.onnx 或 yolov8n.pt)")
        
        # 模型預熱 (Warmup)
        logger.info("🔥 模型預熱中...")
        dummy_img = np.zeros((640, 640, 3), dtype=np.uint8)
        model(dummy_img, imgsz=640, verbose=False)
        del dummy_img
        gc.collect()
        
        logger.info("✅ YOLOv8n 模型載入並預熱完成")
        
    except Exception as e:
        logger.error(f"❌ 模型載入失敗: {e}")
        raise
    
    yield  # 應用運行中
    
    # 關閉階段 - 清理資源
    logger.info("正在關閉應用並清理資源...")
    model = None
    gc.collect()

# 初始化 FastAPI (使用 lifespan)
app = FastAPI(
    title="Crowd Density Detection API",
    description="AI 驅動的群眾密度監控、警報與自動建議",
    version="1.0.0",
    lifespan=lifespan
)

# CORS 設定
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============== Pydantic 模型定義 ==============
class BoundingBox(BaseModel):
    """人員邊界框"""
    x1: int
    y1: int
    x2: int
    y2: int
    confidence: float

class DetectionResult(BaseModel):
    """偵測結果回應"""
    person_count: int
    density: float
    status: str  # "normal", "warning", "danger"
    bounding_boxes: List[BoundingBox]
    image_width: int
    image_height: int
    roi_area_m2: float
    density_warn_threshold: float
    density_danger_threshold: float
    message: str

# ============== 核心偵測函式 ==============
def detect_people(img_bgr: np.ndarray, conf_threshold: float = 0.5) -> tuple:
    """
    使用 YOLOv8n 偵測人員
    
    Args:
        img_bgr: OpenCV BGR 格式圖片
        conf_threshold: 信心度門檻
    
    Returns:
        (person_count, bounding_boxes)
    
    優化: 使用 imgsz=640 減少記憶體佔用, verbose=False 減少日誌
    """
    # 記憶體優化: 限制推論尺寸 640x640, 關閉詳細日誌
    results = model(img_bgr, conf=conf_threshold, classes=[0], imgsz=640, verbose=False)
    boxes = results[0].boxes
    
    person_count = 0
    bounding_boxes = []
    
    for box in boxes:
        if int(box.cls[0]) == 0:  # 確保是人類
            person_count += 1
            x1, y1, x2, y2 = map(int, box.xyxy[0])
            confidence = float(box.conf[0])
            bounding_boxes.append({
                "x1": x1,
                "y1": y1,
                "x2": x2,
                "y2": y2,
                "confidence": confidence
            })
    
    # 記憶體清理
    del results
    del boxes
    gc.collect()
    
    return person_count, bounding_boxes

def calculate_density_status(density: float, warn_threshold: float, danger_threshold: float) -> tuple:
    """
    根據密度計算狀態
    
    Returns:
        (status, message)
    """
    if density >= danger_threshold:
        return "danger", f"⚠️ 危險！密度達 {density:.2f} 人/㎡，請立即疏散人群"
    elif density >= warn_threshold:
        return "warning", f"⚠️ 警告！密度達 {density:.2f} 人/㎡，建議控制人流"
    else:
        return "normal", f"✅ 正常。當前密度 {density:.2f} 人/㎡"

def apply_roi(img: np.ndarray, x0p: int, y0p: int, x1p: int, y1p: int) -> tuple:
    """
    應用 ROI (Region of Interest) 百分比裁切
    
    Args:
        img: 原始圖片
        x0p, y0p, x1p, y1p: ROI 百分比座標 (0-100)
    
    Returns:
        (roi_image, (x0, y0, x1, y1))
    """
    H, W = img.shape[:2]
    x0 = max(0, int(W * x0p / 100.0))
    y0 = max(0, int(H * y0p / 100.0))
    x1 = min(W, int(W * x1p / 100.0))
    y1 = min(H, int(H * y1p / 100.0))
    
    roi = img[y0:y1, x0:x1].copy()
    return roi, (x0, y0, x1, y1)

# ============== n8n Webhook 整合 ==============
async def send_alert_to_n8n(detection_result: DetectionResult):
    """
    發送警報到 n8n webhook (非阻塞)
    
    實作警報節流機制,避免頻繁發送
    """
    global last_alert_time
    
    # 警報節流: 檢查是否在冷卻期內
    now = datetime.now()
    if last_alert_time is not None:
        elapsed = (now - last_alert_time).total_seconds()
        if elapsed < ALERT_COOLDOWN_SECONDS:
            logger.debug(f"警報冷卻中,剩餘 {ALERT_COOLDOWN_SECONDS - elapsed:.1f} 秒")
            return
    
    try:
        # 準備 webhook payload
        payload = {
            "timestamp": now.isoformat(),
            "alert_type": detection_result.status,
            "should_notify": True,  # 後端已判斷需要發送通知
            "person_count": detection_result.person_count,
            "density": detection_result.density,
            "density_unit": "人/㎡",
            "roi_area_m2": detection_result.roi_area_m2,
            "warn_threshold": detection_result.density_warn_threshold,
            "danger_threshold": detection_result.density_danger_threshold,
            "message": detection_result.message,
            "image_dimensions": {
                "width": detection_result.image_width,
                "height": detection_result.image_height
            },
            "detection_count": len(detection_result.bounding_boxes)
        }
        
        # 非同步發送 (timeout 5 秒)
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.post(N8N_WEBHOOK_URL, json=payload)
            
            if response.status_code == 200:
                logger.info(f"✅ 成功發送警報到 n8n: {detection_result.status}")
                last_alert_time = now
            else:
                logger.warning(f"⚠️ n8n webhook 回應異常: {response.status_code}")
                logger.warning(f"回應內容: {response.text[:500]}")
                logger.warning(f"回應 Headers: {dict(response.headers)}")
                
    except httpx.TimeoutException:
        logger.error("❌ n8n webhook 請求超時 (5 秒)")
    except Exception as e:
        logger.error(f"❌ 發送 n8n webhook 失敗: {e}")

# ============== API 端點 ==============
@app.get("/api/health")
async def health_check():
    """健康檢查端點"""
    return {
        "status": "healthy",
        "model_loaded": model is not None,
        "service": "Crowd Density Detection API",
        "version": "1.0.0"
    }

@app.post("/api/detect", response_model=DetectionResult)
async def detect_crowd_density(
    file: UploadFile = File(..., description="要偵測的圖片檔案"),
    roi_area_m2: float = Form(20.0, description="監控區域實際面積 (㎡)"),
    density_warn: float = Form(5.0, description="警告門檻 (人/㎡)"),
    density_danger: float = Form(6.5, description="危險門檻 (人/㎡)"),
    roi_x0: int = Form(0, description="ROI 左邊界百分比 (0-100)"),
    roi_y0: int = Form(0, description="ROI 上邊界百分比 (0-100)"),
    roi_x1: int = Form(100, description="ROI 右邊界百分比 (0-100)"),
    roi_y1: int = Form(100, description="ROI 下邊界百分比 (0-100)"),
    conf_threshold: float = Form(0.5, description="偵測信心度門檻 (0-1)")
):
    """
    群眾密度偵測 API
    
    接收圖片並返回:
    - 人數統計
    - 密度計算 (人/㎡)
    - 警報狀態 (normal/warning/danger)
    - 人員邊界框座標
    """
    try:
        # 檢查模型
        if model is None:
            raise HTTPException(status_code=503, detail="模型尚未載入")
        
        # 讀取圖片
        contents = await file.read()
        image = Image.open(io.BytesIO(contents)).convert('RGB')
        
        # 記憶體優化: 限制圖片尺寸 (最大 1280x1280)
        image.thumbnail((1280, 1280), Image.Resampling.LANCZOS)
        
        # 釋放原始 bytes
        del contents
        gc.collect()
        
        img_np = np.array(image)
        img_bgr = cv2.cvtColor(img_np, cv2.COLOR_RGB2BGR)
        
        # 清理中間變數
        del image
        del img_np
        gc.collect()
        
        original_height, original_width = img_bgr.shape[:2]
        
        # 應用 ROI (如果需要)
        if roi_x0 > 0 or roi_y0 > 0 or roi_x1 < 100 or roi_y1 < 100:
            roi_img, (x0, y0, x1, y1) = apply_roi(img_bgr, roi_x0, roi_y0, roi_x1, roi_y1)
            logger.info(f"應用 ROI: ({x0}, {y0}) -> ({x1}, {y1})")
        else:
            roi_img = img_bgr
            x0, y0 = 0, 0
        
        # 執行偵測
        person_count, boxes = detect_people(roi_img, conf_threshold)
        
        # 將 ROI 內的座標轉換回原圖座標
        global_boxes = [
            BoundingBox(
                x1=box["x1"] + x0,
                y1=box["y1"] + y0,
                x2=box["x2"] + x0,
                y2=box["y2"] + y0,
                confidence=box["confidence"]
            )
            for box in boxes
        ]
        
        # 計算密度
        density = person_count / max(roi_area_m2, 1e-6)
        status, message = calculate_density_status(density, density_warn, density_danger)
        
        logger.info(f"偵測完成: {person_count} 人, 密度 {density:.2f} 人/㎡, 狀態: {status}")
        
        result = DetectionResult(
            person_count=person_count,
            density=round(density, 2),
            status=status,
            bounding_boxes=global_boxes,
            image_width=original_width,
            image_height=original_height,
            roi_area_m2=roi_area_m2,
            density_warn_threshold=density_warn,
            density_danger_threshold=density_danger,
            message=message
        )
        
        # 🚨 發送警報到 n8n (非阻塞)
        if ENABLE_N8N_ALERTS and status in ["warning", "danger"]:
            await send_alert_to_n8n(result)
        
        # 最終記憶體清理
        del img_bgr
        del roi_img
        del boxes
        del global_boxes
        gc.collect()
        
        return result
        
    except Exception as e:
        logger.error(f"偵測錯誤: {e}")
        # 錯誤處理時也要清理記憶體
        gc.collect()
        raise HTTPException(status_code=500, detail=f"偵測失敗: {str(e)}")

@app.post("/api/alert")
async def send_alert_webhook(
    alert_type: str = Form("warning", description="警報類型: normal/warning/danger"),
    person_count: int = Form(25, description="人數"),
    density: float = Form(5.5, description="密度 (人/㎡)"),
    roi_area_m2: float = Form(20.0, description="監控區域面積 (㎡)"),
    warn_threshold: float = Form(5.0, description="警告門檻"),
    danger_threshold: float = Form(6.5, description="危險門檻")
):
    """
    手動發送警報到 n8n
    
    直接發送警報到 n8n webhook，可用於測試或手動觸發警報
    """
    try:
        if not ENABLE_N8N_ALERTS:
            return {
                "success": False,
                "message": "n8n 警報功能已停用 (ENABLE_N8N_ALERTS=false)",
                "webhook_url": N8N_WEBHOOK_URL
            }
        
        # 構建測試用的 DetectionResult
        test_result = DetectionResult(
            person_count=person_count,
            density=round(density, 2),
            status=alert_type,
            bounding_boxes=[],
            image_width=1280,
            image_height=720,
            roi_area_m2=roi_area_m2,
            density_warn_threshold=warn_threshold,
            density_danger_threshold=danger_threshold,
            message=f"🧪 測試警報 - {alert_type} 等級"
        )
        
        # 發送到 n8n
        await send_alert_to_n8n(test_result)
        
        return {
            "success": True,
            "message": "警報已發送",
            "webhook_url": N8N_WEBHOOK_URL,
            "payload": {
                "alert_type": alert_type,
                "person_count": person_count,
                "density": density,
                "roi_area_m2": roi_area_m2
            },
            "note": "請檢查 Discord 頻道是否收到訊息"
        }
        
    except Exception as e:
        logger.error(f"發送警報失敗: {e}")
        raise HTTPException(status_code=500, detail=f"測試失敗: {str(e)}")

@app.get("/")
async def root():
    """根端點 - API 資訊"""
    return {
        "service": "Crowd Density Detection API",
        "version": "1.0.0",
        "description": "AI 驅動的群眾密度監控 - FastAPI + YOLOv8n",
        "endpoints": {
            "health": "/api/health (GET)",
            "detect": "/api/detect (POST)",
            "alert": "/api/alert (POST) - 手動發送警報到 n8n",
            "docs": "/docs"
        },
        "tech_stack": {
            "backend": "FastAPI",
            "model": "YOLOv8n",
            "port": 8001
        },
        "n8n_integration": {
            "enabled": ENABLE_N8N_ALERTS,
            "webhook_url": N8N_WEBHOOK_URL if ENABLE_N8N_ALERTS else "disabled",
            "cooldown_seconds": ALERT_COOLDOWN_SECONDS
        }
    }

# ============== 主程式入口 ==============
if __name__ == "__main__":
    import uvicorn
    # 記憶體優化配置: 單 worker, 限制併發
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8001,
        reload=False,  # 生產環境關閉 reload 減少記憶體
        log_level="info",
        workers=1,  # 單 worker 減少記憶體佔用
        limit_concurrency=5  # 限制同時處理的請求數
    )