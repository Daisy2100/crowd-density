#!/bin/bash

# Crowd Density Detection Quick Setup Script (Linux/macOS)
# This script will automatically setup environment and start the project

echo "========================================"
echo "Crowd Density Detection Quick Setup"
echo "========================================"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# Step 1: Check Python
echo -e "${YELLOW}Step 1/2: Checking Python...${NC}"

PYTHON_CMD=""
for cmd in python3 python; do
    if command -v $cmd &> /dev/null; then
        PYTHON_CMD=$cmd
        break
    fi
done

if [ -z "$PYTHON_CMD" ]; then
    echo -e "${RED}Python not found, please install Python 3.8+${NC}"
    exit 1
fi

PYTHON_VERSION=$($PYTHON_CMD --version)
echo -e "${GREEN}$PYTHON_VERSION${NC}"

# Step 2: Check Node.js
echo ""
echo -e "${YELLOW}Step 2/2: Checking Node.js...${NC}"

if ! command -v node &> /dev/null; then
    echo -e "${RED}Node.js not detected, frontend cannot start${NC}"
    echo -e "${YELLOW}Download: https://nodejs.org/${NC}"
    echo -e "${YELLOW}Continue with backend only? (y/N)${NC}"
    read -r continue_choice
    if [ "$continue_choice" != "y" ] && [ "$continue_choice" != "Y" ]; then
        exit 1
    fi
else
    NODE_VERSION=$(node --version)
    echo -e "${GREEN}Node.js version: $NODE_VERSION${NC}"
fi

# Choose startup method
echo ""
echo -e "${YELLOW}Choose startup method:${NC}"
echo "1. Full setup (Backend + Frontend)"
echo "2. Backend only (Docker) - for deployment"
echo "3. Backend only (Local Python) - recommended for development"
echo "4. Frontend only (Vite dev server)"
echo "5. Setup only, show manual commands"

read -p "Choose (1-5): " choice

case $choice in
    1)
        echo ""
        echo -e "${YELLOW}Starting full setup...${NC}"
        
        # Check Docker
        if ! command -v docker &> /dev/null; then
            echo -e "${RED}Docker not found. Please use option 3 (Local Python) for backend.${NC}"
            echo -e "${YELLOW}Or install Docker: https://www.docker.com/products/docker-desktop${NC}"
            exit 1
        fi
        
        # Start backend services with Docker
        echo -e "${YELLOW}Starting backend services (Backend + n8n) with Docker...${NC}"
        if command -v docker-compose &> /dev/null; then
            docker-compose up -d --build || { echo -e "${RED}Backend startup failed${NC}"; exit 1; }
        else
            docker compose up -d --build || { echo -e "${RED}Backend startup failed${NC}"; exit 1; }
        fi
        
        echo -e "${GREEN}Backend services started${NC}"
        
        # Install frontend dependencies
        if [ -f "frontend/package.json" ]; then
            echo ""
            echo -e "${YELLOW}Installing frontend dependencies...${NC}"
            cd frontend
            if [ ! -d "node_modules" ]; then
                npm install
            fi
            cd ..
        fi
        
        # Wait for backend ready
        echo ""
        echo -e "${YELLOW}Waiting for backend services...${NC}"
        sleep 10
        
        # Display info
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}Full Setup Completed!${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        
        echo -e "${CYAN}Backend is running:${NC}"
        echo "  API: http://localhost:8001"
        echo "  Docs: http://localhost:8001/docs"
        echo "  n8n: http://localhost:5678 (admin/admin123)"
        echo ""
        
        echo -e "${YELLOW}To start frontend:${NC}"
        echo "  cd frontend"
        echo "  npm run dev"
        echo "  Frontend will be at http://localhost:5173"
        ;;
        
    2)
        echo ""
        echo -e "${YELLOW}Starting backend only (Docker)...${NC}"
        
        if ! command -v docker &> /dev/null; then
            echo -e "${RED}Docker not found, please install Docker first${NC}"
            echo -e "${YELLOW}Download: https://www.docker.com/products/docker-desktop${NC}"
            exit 1
        fi
        
        if command -v docker-compose &> /dev/null; then
            docker-compose up -d --build || { echo -e "${RED}Backend startup failed${NC}"; exit 1; }
        else
            docker compose up -d --build || { echo -e "${RED}Backend startup failed${NC}"; exit 1; }
        fi
        
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}Backend Started (Docker)!${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        
        echo -e "${CYAN}Access URLs:${NC}"
        echo "  API: http://localhost:8001"
        echo "  Docs: http://localhost:8001/docs"
        echo "  n8n: http://localhost:5678 (admin/admin123)"
        ;;
        
    3)
        echo ""
        echo -e "${YELLOW}Starting backend (Local Python) - recommended for development...${NC}"
        
        if [ ! -f "backend/main.py" ]; then
            echo -e "${RED}Backend folder not found${NC}"
            exit 1
        fi
        
        cd backend
        
        # Check/Create virtual environment
        if [ ! -d "venv" ]; then
            echo -e "${YELLOW}Creating virtual environment...${NC}"
            $PYTHON_CMD -m venv venv
        fi
        
        # Activate venv
        echo -e "${YELLOW}Activating virtual environment...${NC}"
        source venv/bin/activate
        
        # Install dependencies
        echo -e "${YELLOW}Installing dependencies...${NC}"
        pip install -r requirements.txt
        
        # Check model file
        if [ ! -f "yolov8n.pt" ]; then
            echo -e "${YELLOW}YOLOv8 model not found, checking parent directory...${NC}"
            if [ -f "../yolov8n.pt" ]; then
                cp "../yolov8n.pt" "."
                echo -e "${GREEN}Model file copied${NC}"
            else
                echo -e "${YELLOW}Model file not found, will download on first run${NC}"
            fi
        fi
        
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}Backend Starting (Local Python)!${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        
        echo -e "${CYAN}API: http://localhost:8001${NC}"
        echo -e "${CYAN}Docs: http://localhost:8001/docs${NC}"
        echo ""
        echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
        echo ""
        
        # Start FastAPI
        uvicorn main:app --host 0.0.0.0 --port 8001 --reload
        ;;
        
    4)
        echo ""
        echo -e "${YELLOW}Starting frontend only...${NC}"
        
        if [ ! -f "frontend/package.json" ]; then
            echo -e "${RED}Frontend folder not found${NC}"
            exit 1
        fi
        
        cd frontend
        
        if [ ! -d "node_modules" ]; then
            echo -e "${YELLOW}Installing dependencies...${NC}"
            npm install
        fi
        
        echo ""
        echo -e "${GREEN}Starting Vite dev server...${NC}"
        echo -e "${CYAN}Frontend: http://localhost:5173${NC}"
        echo -e "${YELLOW}Backend: http://localhost:8001 (ensure backend is running)${NC}"
        echo ""
        
        npm run dev
        ;;
        
    5)
        echo ""
        echo -e "${YELLOW}Setup completed! Start manually:${NC}"
        echo ""
        echo -e "${CYAN}Backend Docker (Terminal 1):${NC}"
        echo "  docker-compose up -d"
        echo ""
        echo -e "${CYAN}Backend Local (Terminal 1) - recommended for development:${NC}"
        echo "  cd backend"
        echo "  $PYTHON_CMD -m venv venv"
        echo "  source venv/bin/activate"
        echo "  pip install -r requirements.txt"
        echo "  uvicorn main:app --host 0.0.0.0 --port 8001 --reload"
        echo ""
        echo -e "${CYAN}Frontend (Terminal 2):${NC}"
        echo "  cd frontend"
        echo "  npm install"
        echo "  npm run dev"
        ;;
        
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Setup Summary${NC}"
echo -e "${CYAN}========================================${NC}"

echo "System: Crowd Density Detection"
echo "Backend: FastAPI + YOLOv8n (Port 8001)"
echo "Frontend: Vue 3 + Vite (Port 5173)"
echo "Automation: n8n (Port 5678)"

echo ""
echo -e "${CYAN}More Information:${NC}"
echo "  Project Info: README.md"
echo "  GitHub: https://github.com/Katherine623/Crowd-Density-Detection"

echo ""
echo -e "${GREEN}Setup completed! Enjoy!${NC}"
