# ============================================
# Multi-stage build: 從 7GB 優化到 1-2GB
# 策略: 使用 CPU-only PyTorch + 清理 build cache
# ============================================

FROM python:3.11-slim AS builder

WORKDIR /build

# 安裝 build 依賴
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# 複製 requirements
COPY requirements.txt .

# 安裝 CPU-only PyTorch (省 3-4GB CUDA)
RUN pip install --no-cache-dir \
    torch torchvision --index-url https://download.pytorch.org/whl/cpu && \
    pip install --no-cache-dir -r requirements.txt

# ============================================
# Runtime Stage (最終 image)
# ============================================
FROM python:3.11-slim

WORKDIR /app

# 只安裝 runtime 依賴
RUN apt-get update && apt-get install -y \
    libgl1 \
    libglib2.0-0 \
    libgomp1 \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# 從 builder 複製 Python packages
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# 複製應用程式碼和模型
COPY main.py .
COPY yolov8n.pt .

# 設置環境變數
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PORT=8001

# 暴露端口
EXPOSE 8001

# 健康檢查
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8001/api/health || exit 1

# 啟動 FastAPI 應用 (已優化 workers 和 concurrency)
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT} --workers 1 --limit-concurrency 5"]
