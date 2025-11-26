#!/bin/bash

# Crowd Density Backend - Docker Image Build Script

IMAGE_NAME="crowd-density-backend"
IMAGE_TAG="latest"

echo "=========================================="
echo "Building Docker Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "=========================================="

# Build Docker image
docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "✅ Build Success!"
    echo "=========================================="
    echo "Image: ${IMAGE_NAME}:${IMAGE_TAG}"
    echo ""
    echo "Available commands:"
    echo "  docker images | grep ${IMAGE_NAME}"
    echo "  docker run -d -p 8001:8001 --name crowd-backend ${IMAGE_NAME}:${IMAGE_TAG}"
    echo "=========================================="
else
    echo ""
    echo "=========================================="
    echo "❌ Build Failed!"
    echo "=========================================="
    exit 1
fi
