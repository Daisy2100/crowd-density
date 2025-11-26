# Crowd Density Detection Quick Setup Script
# This script will automatically setup environment and start the project

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Crowd Density Detection Quick Setup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Step 1: Check Docker
Write-Host "Step 1/3: Checking Docker..." -ForegroundColor Yellow

$dockerInstalled = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerInstalled) {
    Write-Host "Docker not detected, please install Docker Desktop first" -ForegroundColor Red
    Write-Host "Download: https://www.docker.com/products/docker-desktop" -ForegroundColor Yellow
    exit
}

# Test Docker daemon
try {
    docker version | Out-Null
    Write-Host "Docker environment OK" -ForegroundColor Green
} catch {
    Write-Host "Docker Daemon not running, please start Docker Desktop" -ForegroundColor Red
    exit
}

# Step 2: Check Node.js
Write-Host "`nStep 2/3: Checking Node.js..." -ForegroundColor Yellow

$nodeInstalled = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeInstalled) {
    Write-Host "Node.js not detected, frontend cannot start" -ForegroundColor Red
    Write-Host "Download: https://nodejs.org/" -ForegroundColor Yellow
    Write-Host "Continue with backend only? (y/N)" -ForegroundColor Yellow
    $continue = Read-Host
    if ($continue -ne "y" -and $continue -ne "Y") {
        exit
    }
} else {
    $nodeVersion = node --version
    Write-Host "Node.js version: $nodeVersion" -ForegroundColor Green
}

# Step 3: Choose startup method
Write-Host "`nStep 3/3: Choose startup method..." -ForegroundColor Yellow
Write-Host "1. Full setup (Backend + Frontend)" -ForegroundColor White
Write-Host "2. Backend only (Docker)" -ForegroundColor White
Write-Host "3. Backend only (Local Python)" -ForegroundColor White
Write-Host "4. Frontend only (Vite dev server)" -ForegroundColor White
Write-Host "5. Setup only, start manually later" -ForegroundColor White

$choice = Read-Host "Choose (1-5)"

# Check docker-compose
$composeCmd = "docker-compose"
if (-not (Get-Command docker-compose -ErrorAction SilentlyContinue)) {
    $composeCmd = "docker compose"
}

switch ($choice) {
    "1" {
        Write-Host "`nStarting full setup..." -ForegroundColor Yellow
        
        # Start backend services
        Write-Host "Starting backend services (Backend + n8n)..." -ForegroundColor Yellow
        & $composeCmd up -d --build
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Backend startup failed" -ForegroundColor Red
            exit
        }
        
        Write-Host "Backend services started" -ForegroundColor Green
        
        # Install frontend dependencies
        if (Test-Path "frontend/package.json") {
            Write-Host "`nInstalling frontend dependencies..." -ForegroundColor Yellow
            Push-Location frontend
            if (-not (Test-Path "node_modules")) {
                npm install
            }
            Pop-Location
        }
        
        # Wait for backend ready
        Write-Host "`nWaiting for backend services..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        
        # Display info
        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "Full Setup Completed!" -ForegroundColor Green
        Write-Host "========================================`n" -ForegroundColor Green
        
        Write-Host "Backend is running:" -ForegroundColor Cyan
        Write-Host "  API: http://localhost:8001" -ForegroundColor White
        Write-Host "  Docs: http://localhost:8001/docs" -ForegroundColor White
        Write-Host "  n8n: http://localhost:5678 (admin/admin123)`n" -ForegroundColor White
        
        Write-Host "To start frontend:" -ForegroundColor Yellow
        Write-Host "  cd frontend" -ForegroundColor White
        Write-Host "  npm run dev" -ForegroundColor White
        Write-Host "  Frontend will be at http://localhost:5173`n" -ForegroundColor White
        
        Write-Host "Management commands:" -ForegroundColor Cyan
        Write-Host "  Stop: $composeCmd down" -ForegroundColor White
        Write-Host "  Logs: $composeCmd logs -f" -ForegroundColor White
        Write-Host "  Restart: $composeCmd restart" -ForegroundColor White
    }
    "2" {
        Write-Host "`nStarting backend only..." -ForegroundColor Yellow
        & $composeCmd up -d --build
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Backend startup failed" -ForegroundColor Red
            exit
        }
        
        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "Backend Started!" -ForegroundColor Green
        Write-Host "========================================`n" -ForegroundColor Green
        
        Write-Host "Access URLs:" -ForegroundColor Cyan
        Write-Host "  API: http://localhost:8001" -ForegroundColor White
        Write-Host "  Docs: http://localhost:8001/docs" -ForegroundColor White
        Write-Host "  n8n: http://localhost:5678 (admin/admin123)" -ForegroundColor White
    }
    "3" {
        Write-Host "`nStarting backend (Local Python)..." -ForegroundColor Yellow
        
        if (-not (Test-Path "backend/main.py")) {
            Write-Host "Backend folder not found" -ForegroundColor Red
            exit
        }
        
        Push-Location backend
        
        # Check Python
        $pythonCmd = $null
        foreach ($cmd in @("python", "python3", "py")) {
            if (Get-Command $cmd -ErrorAction SilentlyContinue) {
                $pythonCmd = $cmd
                break
            }
        }
        
        if (-not $pythonCmd) {
            Write-Host "Python not found, please install Python 3.8+" -ForegroundColor Red
            Pop-Location
            exit
        }
        
        $pythonVersion = & $pythonCmd --version
        Write-Host "Using: $pythonVersion" -ForegroundColor Green
        
        # Check/Create virtual environment
        if (-not (Test-Path "venv")) {
            Write-Host "Creating virtual environment..." -ForegroundColor Yellow
            & $pythonCmd -m venv venv
        }
        
        # Activate venv
        Write-Host "Activating virtual environment..." -ForegroundColor Yellow
        & .\venv\Scripts\Activate.ps1
        
        # Install dependencies
        Write-Host "Installing dependencies..." -ForegroundColor Yellow
        pip install -r requirements.txt
        
        # Check model file
        if (-not (Test-Path "yolov8n.pt")) {
            Write-Host "YOLOv8 model not found, copying..." -ForegroundColor Yellow
            if (Test-Path "../yolov8n.pt") {
                Copy-Item "../yolov8n.pt" "."
                Write-Host "Model file copied" -ForegroundColor Green
            } else {
                Write-Host "Model file not found, will download on first run" -ForegroundColor Yellow
            }
        }
        
        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "Backend Starting!" -ForegroundColor Green
        Write-Host "========================================`n" -ForegroundColor Green
        
        Write-Host "API: http://localhost:8001" -ForegroundColor Cyan
        Write-Host "Docs: http://localhost:8001/docs" -ForegroundColor Cyan
        Write-Host "`nPress Ctrl+C to stop`n" -ForegroundColor Yellow
        
        # Start FastAPI
        uvicorn main:app --host 0.0.0.0 --port 8001 --reload
        
        Pop-Location
    }
    "4" {
        Write-Host "`nStarting frontend only..." -ForegroundColor Yellow
        
        if (-not (Test-Path "frontend/package.json")) {
            Write-Host "Frontend folder not found" -ForegroundColor Red
            exit
        }
        
        Push-Location frontend
        
        if (-not (Test-Path "node_modules")) {
            Write-Host "Installing dependencies..." -ForegroundColor Yellow
            npm install
        }
        
        Write-Host "`nStarting Vite dev server..." -ForegroundColor Green
        Write-Host "Frontend: http://localhost:5173" -ForegroundColor Cyan
        Write-Host "Backend: http://localhost:8001 (ensure backend is running)`n" -ForegroundColor Yellow
        
        npm run dev
        
        Pop-Location
    }
    "5" {
        Write-Host "`nSetup completed! Start manually:" -ForegroundColor Yellow
        Write-Host "`nBackend Docker (Terminal 1):" -ForegroundColor Cyan
        Write-Host "  $composeCmd up -d" -ForegroundColor White
        Write-Host "`nBackend Local (Terminal 1):" -ForegroundColor Cyan
        Write-Host "  cd backend" -ForegroundColor White
        Write-Host "  python -m venv venv" -ForegroundColor White
        Write-Host "  .\venv\Scripts\Activate.ps1" -ForegroundColor White
        Write-Host "  pip install -r requirements.txt" -ForegroundColor White
        Write-Host "  uvicorn main:app --host 0.0.0.0 --port 8001 --reload" -ForegroundColor White
        Write-Host "`nFrontend (Terminal 2):" -ForegroundColor Cyan
        Write-Host "  cd frontend" -ForegroundColor White
        Write-Host "  npm install" -ForegroundColor White
        Write-Host "  npm run dev" -ForegroundColor White
    }
    default {
        Write-Host "`nInvalid choice" -ForegroundColor Red
        exit
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Setup Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "System: Crowd Density Detection" -ForegroundColor White
Write-Host "Backend: FastAPI + YOLOv8n (Port 8001)" -ForegroundColor White
Write-Host "Frontend: Vue 3 + Vite (Port 5173)" -ForegroundColor White
Write-Host "Automation: n8n (Port 5678)" -ForegroundColor White

Write-Host "`nMore Information:" -ForegroundColor Cyan
Write-Host "  Project Info: README.md" -ForegroundColor White
Write-Host "  GitHub: https://github.com/Katherine623/Crowd-Density-Detection" -ForegroundColor White

Write-Host "`nSetup completed! Enjoy!" -ForegroundColor Green
