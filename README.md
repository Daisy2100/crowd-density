# 群眾密度監控系統 | Crowd Density Detection System

> **AI 驅動的即時人流監控、智能警報與自動建議系統**  
> 基於 YOLOv8、FastAPI、Vue 3 與 n8n 的企業級解決方案

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-Supported-2496ED?logo=docker)](https://www.docker.com/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.109-009688?logo=fastapi)](https://fastapi.tiangolo.com/)
[![Vue 3](https://img.shields.io/badge/Vue-3.4-4FC08D?logo=vue.js)](https://vuejs.org/)

---

## 📖 目錄

- [專案概述](#專案概述)
- [系統架構](#系統架構)
- [快速開始](#快速開始)
- [專案結構](#專案結構)
- [API 文檔](#api-文檔)
- [n8n 工作流配置](#n8n-工作流配置)
- [部署指南](#部署指南)

---

## 專案概述

本系統是一套完整的 **AI 驅動群眾密度監控解決方案**，整合電腦視覺、自動化工作流與智能推理。

---

## 系統架構

### I. 基礎設施與部署環境

| **項目** | **配置與決策** | **說明** |
| --- | --- | --- |
| **系統目標** | AI 驅動的群眾密度監控、警報與自動建議 | 辨識 → 推理 → 行動 (通知) |
| **主機環境** | GCP Compute Engine **`e2-medium` (4GB RAM)** | 穩定運行 YOLO 和 n8n |
| **資料持久化** | **n8n 內建 SQLite** | 儲存工作流、執行紀錄和憑證 |

### II. 應用程式服務與角色

| **服務** | **技術棧** | **核心功能** | **端口** |
| --- | --- | --- | --- |
| **後端 API** (Vision) | **FastAPI + YOLOv8n** | 接收圖片 ⇒ 偵測 ⇒ 回傳結果 | 8001 |
| **自動化核心** (Brain) | **n8n** | 排程、條件判斷、整合 Vertex AI | 5678 |
| **前端 UI** (Dashboard) | **Vue 3 + Vite** | Webcam 截圖,**2000ms 間隔**呼叫 API | 5173 |

### III. 關鍵數據流與邏輯

| **數據流** | **執行頻率** | **流程** | **輸出** |
| --- | --- | --- | --- |
| **1. 即時監控流** | **2000 毫秒** (0.5 FPS) | Vue → FastAPI → Vue | 網頁儀表板 |
| **2. 自動警報流** | **30 秒 - 1 分鐘** | n8n → FastAPI → Vertex AI → Discord | AI 建議警報 |

### IV. AI 與通知優化

- **視覺 (Vision):** **YOLOv8n** - 在共享 CPU 環境快速推論
- **大腦 (Reasoning):** **Google Vertex AI (Gemini)** - 生成人性化警報文案
- **警報服務:** **Telegram / Discord** - 免費且無限量推播

---

## 快速開始

### 前置需求

- **Docker Desktop** - [下載安裝](https://www.docker.com/products/docker-desktop/)
- **Node.js 20+** - [下載安裝](https://nodejs.org/)
- **Git** - [下載安裝](https://git-scm.com/)
- **Webcam** - (前端監控功能需要)

### 安裝步驟

#### 1️⃣ 克隆專案

```bash
git clone https://github.com/Katherine623/Crowd-Density-Detection.git
cd Crowd-Density-Detection
```

#### 2️⃣ 啟動後端服務 (Windows)

```powershell
# 一鍵啟動後端與 n8n
.\setup.ps1
```

#### 2️⃣ 啟動後端服務 (Linux/macOS)

```bash
# 啟動後端與 n8n
docker-compose up -d --build

# 查看服務狀態
docker-compose ps
```

#### 3️⃣ 啟動前端 (開發模式)

```bash
cd frontend
npm install
npm run dev
```

#### 4️⃣ 訪問服務

- **前端介面:** http://localhost:5173
- **後端 API:** http://localhost:8001
- **API 文檔:** http://localhost:8001/docs
- **n8n 平台:** http://localhost:5678 (帳號: `admin` / 密碼: `admin123`)

---

## 專案結構

```plaintext
crowd-density/
├── backend/                      # FastAPI 後端
│   ├── main.py                   # FastAPI 應用入口
│   ├── requirements.txt          # Python 依賴
│   ├── yolov8n.pt               # YOLOv8 模型檔案
│   ├── Dockerfile               # 後端容器配置
│   ├── deploy.ps1               # Windows 打包腳本
│   └── build.sh                 # Linux 建置腳本
├── frontend/                     # Vue 3 前端
│   ├── src/
│   │   ├── App.vue              # 主應用元件
│   │   ├── main.ts              # 應用入口
│   │   ├── style.css            # 全域樣式
│   │   └── vite-env.d.ts        # TypeScript 環境定義
│   ├── package.json             # Node.js 依賴
│   ├── vite.config.ts           # Vite 建置配置
│   ├── tsconfig.json            # TypeScript 配置
│   ├── .env.development         # 開發環境配置
│   └── .env.production          # 生產環境配置
├── docker-compose.yaml          # 多服務編排配置
├── setup.ps1                    # 快速設置腳本 (Windows)
├── app.py                       # [舊版] Streamlit 應用 (保留)
├── requirements.txt             # [舊版] Python 依賴 (保留)
└── README.md                    # 專案文檔 (本文件)
```

---

## API 文檔

### 端點總覽

| 方法 | 端點 | 說明 |
| --- | --- | --- |
| `GET` | `/` | API 根路徑資訊 |
| `GET` | `/api/healthy` | 健康檢查 |
| `POST` | `/api/detect` | 人員偵測與密度分析 |

### `POST /api/detect`

**功能:** 上傳圖片進行人員偵測與密度計算

**請求參數:**

| 參數 | 類型 | 必填 | 預設值 | 說明 |
| --- | --- | --- | --- | --- |
| `file` | File | ✅ | - | 圖片檔案 (JPEG/PNG) |
| `roi_area_m2` | float | ❌ | 20.0 | 監控區域面積 (平方公尺) |
| `density_warn` | float | ❌ | 5.0 | 警告閾值 (人/㎡) |
| `density_danger` | float | ❌ | 6.5 | 危險閾值 (人/㎡) |

**回應範例:**

```json
{
  "person_count": 12,
  "density": 0.6,
  "status": "normal",
  "bounding_boxes": [
    {
      "x1": 120,
      "y1": 80,
      "x2": 200,
      "y2": 300,
      "confidence": 0.92
    }
  ],
  "image_width": 1280,
  "image_height": 720,
  "roi_area_m2": 20.0
}
```

**互動式文檔:** http://localhost:8001/docs

---

## n8n 工作流配置

### 範例工作流: 自動警報系統

#### 流程設計

```plaintext
[排程觸發 (Cron)]
    ↓
[HTTP Request - 呼叫 Backend API]
    ↓
[條件判斷 - 檢查 status]
    ↓ (warning 或 danger)
[Vertex AI - 生成警報文案]
    ↓
[Discord/Telegram - 發送通知]
```

#### 配置步驟

1. **登入 n8n:** http://localhost:5678 (admin / admin123)
2. **建立新工作流:** 點擊 "New Workflow"
3. **新增節點:**
   - **Schedule Trigger** - 每 1 分鐘執行
   - **HTTP Request** - 呼叫 `http://backend:8001/api/detect`
   - **IF** - 判斷 `status !== "normal"`
   - **Vertex AI** - 生成 AI 建議
   - **Discord/Telegram** - 發送通知

---

## 部署指南

### 本地開發部署

#### 後端服務 (Docker)

```bash
# 啟動後端與 n8n
docker-compose up -d --build

# 查看狀態
docker-compose ps

# 停止服務
docker-compose down
```

#### 前端服務 (Vite)

```bash
cd frontend
npm install
npm run dev
```

前端將在 http://localhost:5173 啟動

---

## 常見問題

### Q1: Docker 建置失敗

**A:** 檢查 Docker Desktop 是否正常運行

```bash
docker version
```

### Q2: 前端無法連接後端

**A:** 確認後端服務正常運行、防火牆未阻擋 8001 端口

### Q3: n8n 無法訪問 Backend

**A:** 使用容器內部網路 URL: `http://backend:8001`

### Q4: Webcam 無法啟動

**A:** 瀏覽器需要 HTTPS 或 localhost 才能訪問 Webcam

---

## 授權

本專案採用 **MIT License** 授權。

---

## 聯絡資訊

- **作者:** Katherine623
- **GitHub:** [@Katherine623](https://github.com/Katherine623)
- **專案連結:** [Crowd-Density-Detection](https://github.com/Katherine623/Crowd-Density-Detection)

---

## 致謝

- [Ultralytics YOLOv8](https://github.com/ultralytics/ultralytics)
- [FastAPI](https://fastapi.tiangolo.com/)
- [Vue.js](https://vuejs.org/)
- [n8n](https://n8n.io/)
- [Google Vertex AI](https://cloud.google.com/vertex-ai)

---

⭐ **如果這個專案對您有幫助,歡迎給個星星支持！**

---

**最後更新:** 2025-11-26  
**版本:** 1.0.0
