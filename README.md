# 群眾密度監控系統 | Crowd Density Detection System

> **AI 驅動的即時人流監控與智能警報系統**  
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

本系統是一套完整的 **AI 驅動群眾密度監控解決方案**，整合電腦視覺、自動化工作流與即時警報通知。

---

## 系統架構

### I. 基礎設施與部署環境

| **項目** | **配置與決策** | **說明** |
| --- | --- | --- |
| **系統目標** | AI 驅動的群眾密度監控與即時警報 | 辨識 → 判斷 → 通知 |
| **主機環境** | GCP Compute Engine **`e2-small` (2GB RAM)** | 穩定運行 YOLO 和 n8n |
| **資料持久化** | **n8n 內建 SQLite** | 儲存工作流、執行紀錄和憑證 |

### II. 應用程式服務與角色

| **服務** | **技術棧** | **核心功能** | **端口** |
| --- | --- | --- | --- |
| **後端 API** (Vision) | **FastAPI + YOLOv8n** | 接收圖片 ⇒ 偵測 ⇒ 回傳結果 | 8001 |
| **自動化核心** (Brain) | **n8n** | 排程、條件判斷、Discord 警報推送 | 5678 |
| **前端 UI** (Dashboard) | **Vue 3** | Webcam 截圖,**1000ms 間隔**呼叫 API | 5173 |

### III. 關鍵數據流與邏輯

| **數據流** | **執行頻率** | **流程** | **輸出** |
| --- | --- | --- | --- |
| **1. 即時監控流** | **1000 毫秒** (1 FPS) | Vue → FastAPI → Vue | 網頁儀表板 |
| **2. 自動警報流** | **觸發式** (冷卻 60 秒) | FastAPI → n8n → Discord | 即時警報推送 |

### IV. AI 與通知優化

- **視覺 (Vision):** **YOLOv8n** - 在共享 CPU 環境快速推論
- **警報服務:** **Discord** - 免費且即時的通知推播

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
# 一鍵啟動 (推薦)
./setup.sh
```

**或手動啟動 (推薦開發使用):**

```bash
# 進入後端目錄
cd backend

# 建立虛擬環境
python3 -m venv venv
source venv/bin/activate

# 安裝依賴
pip install -r requirements.txt

# 啟動後端服務
uvicorn main:app --host 0.0.0.0 --port 8001 --reload
```

> 💡 **注意:** Docker 方式 (`docker-compose up -d --build`) 建議用於**生產部署**，而非日常開發。

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
- **n8n 平台:** http://localhost:5678

---

## 專案結構

```plaintext
crowd-density/
├── backend/                      # FastAPI 後端
│   ├── main.py                   # FastAPI 應用入口
│   ├── requirements.txt          # Python 依賴
│   ├── yolov8n.pt               # YOLOv8 模型檔案
│   ├── .env                     # 環境變數配置 (本地開發)
│   └── .env.example             # 環境變數範例
├── frontend/                     # Vue 3 前端
│   ├── src/
│   │   ├── App.vue              # 主應用元件
│   │   ├── main.ts              # 應用入口
│   │   ├── style.css            # 全域樣式
│   │   └── vite-env.d.ts        # TypeScript 環境定義
│   ├── package.json             # Node.js 依賴
│   ├── vite.config.ts           # Vite 建置配置
│   └── tsconfig.json            # TypeScript 配置
├── setup.ps1                    # 快速設置腳本 (Windows)
├── setup.sh                     # 快速設置腳本 (Linux/macOS)
└── README.md                    # 專案文檔 (本文件)
```



## 警報系統

後端發送到 n8n 的數據格式:

```json
{
  "timestamp": "2025-11-30T12:34:56",
  "alert_type": "danger",
  "should_notify": true,
  "person_count": 35,
  "density": 7.5,
  "density_unit": "人/㎡",
  "roi_area_m2": 20.0,
  "warn_threshold": 5.0,
  "danger_threshold": 6.5,
  "message": "⚠️ 危險！密度達 7.50 人/㎡，請立即疏散人群",
  "image_dimensions": {
    "width": 1280,
    "height": 720
  },
  "detection_count": 35
}
```

---

## 聯絡資訊

- **作者:** Katherine623、Daisy2100
- **GitHub:** 
  - [@Katherine623](https://github.com/Katherine623)
  - [@Daisy2100](https://github.com/Daisy2100)
- **專案連結:** 
  - [Crowd-Density-Detection (Katherine623)](https://github.com/Katherine623/Crowd-Density-Detection)
  - [crowd-density (Daisy2100)](https://github.com/Daisy2100/crowd-density)

---

## 致謝

- [Ultralytics YOLOv8](https://github.com/ultralytics/ultralytics)
- [FastAPI](https://fastapi.tiangolo.com/)
- [Vue.js](https://vuejs.org/)
- [n8n](https://n8n.io/)

---

## 授權

本專案採用 **MIT License** 授權。

---

⭐ **如果這個專案對您有幫助,歡迎給個星星支持！**
