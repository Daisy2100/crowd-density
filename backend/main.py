"""
群眾密度監控 FastAPI 後端
Vision Layer - 使用 YOLOv8n 進行人群偵測與密度計算
內部 Port: 8001
"""

from fastapi import FastAPI, File, UploadFile, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from ultralytics import YOLO
from PIL import Image
import cv2
import numpy as np
import io
from typing import List, Dict, Optional
from pydantic import BaseModel
import logging
import torch

# 設定日誌
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# 初始化 FastAPI
app = FastAPI(
    title="Crowd Density Detection API",
    description="AI 驅動的群眾密度監控、警報與自動建議",
    version="1.0.0"
)

# CORS 設定 - 允許前端存取
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 生產環境應限制特定來源
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 全域模型載入 (啟動時載入一次)
model = None

@app.on_event("startup")
async def load_yolo_model():
    """應用啟動時載入 YOLOv8n 模型"""
    global model
    try:
        logger.info("載入 YOLOv8n 模型...")
        
        # 修復 PyTorch 2.6+ weights_only 預設值問題
        # 保存原始的 torch.load 函數
        original_torch_load = torch.load
        
        # 創建包裝函數，強制 weights_only=False
        def patched_torch_load(*args, **kwargs):
            # 如果沒有明確設置 weights_only，則設為 False（信任 YOLOv8n 官方模型）
            if 'weights_only' not in kwargs:
                kwargs['weights_only'] = False
            return original_torch_load(*args, **kwargs)
        
        # 替換 torch.load
        torch.load = patched_torch_load
        logger.info("已修補 torch.load 以載入可信任的 YOLOv8n 模型")
        
        model = YOLO("yolov8n.pt")
        
        # 恢復原始函數（可選）
        torch.load = original_torch_load
        
        logger.info("✅ YOLOv8n 模型載入成功")
    except Exception as e:
        logger.error(f"❌ 模型載入失敗: {e}")
        raise

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
    """
    results = model(img_bgr, conf=conf_threshold, classes=[0])  # class 0 = person
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
        img_np = np.array(image)
        img_bgr = cv2.cvtColor(img_np, cv2.COLOR_RGB2BGR)
        
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
        
        return DetectionResult(
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
        
    except Exception as e:
        logger.error(f"偵測錯誤: {e}")
        raise HTTPException(status_code=500, detail=f"偵測失敗: {str(e)}")

@app.get("/")
async def root():
    """根端點 - API 資訊"""
    return {
        "service": "Crowd Density Detection API",
        "version": "1.0.0",
        "description": "AI 驅動的群眾密度監控 - FastAPI + YOLOv8n",
        "endpoints": {
            "health": "/health",
            "detect": "/api/detect (POST)",
            "docs": "/docs"
        },
        "tech_stack": {
            "backend": "FastAPI",
            "model": "YOLOv8n",
            "port": 8001
        }
    }

# ============== 主程式入口 ==============
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8001,
        reload=True,
        log_level="info"
    )