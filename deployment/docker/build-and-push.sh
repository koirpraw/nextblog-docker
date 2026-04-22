#!/bin/bash
set -e

# Build and Push Docker Image to Docker Hub
# Run this locally or in CI/CD before creating Golden AMI
#
# IMPORTANT: This script builds for linux/amd64 platform to ensure
# compatibility with EC2 t3.micro/t2.micro instances (AMD64 architecture).
# If building on Apple Silicon Mac (M1/M2/M3), Docker will cross-compile.

echo "=========================================="
echo "Building and Pushing Docker Image"
echo "=========================================="

# Configuration - UPDATE THESE
DOCKER_USERNAME="praweg"  # Your Docker Hub username
IMAGE_NAME="nextjs-blog"
IMAGE_TAG="latest"  # or use version tags like "v1.0.0"

FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "Building image: $FULL_IMAGE_NAME"
echo ""

# Build the Docker image
echo "Step 1: Building Docker image..."
echo "Building for linux/amd64 platform (EC2 compatibility)..."
docker build --platform linux/amd64 -t $FULL_IMAGE_NAME .

echo "✓ Image built successfully"
echo ""

# Show image size
echo "Image details:"
docker images | grep $IMAGE_NAME | head -1

echo ""
echo "Step 2: Logging in to Docker Hub..."
echo "Please enter your Docker Hub credentials:"
docker login

echo ""
echo "Step 3: Pushing image to Docker Hub..."
docker push $FULL_IMAGE_NAME

echo ""
echo "=========================================="
echo "✓ Image pushed successfully!"
echo "=========================================="
echo ""
echo "Image available at:"
echo "  docker pull $FULL_IMAGE_NAME"
echo ""
echo "Next steps:"
echo "1. Update deployment/docker/setup-golden-ami-docker-pull.sh"
echo "2. Set DOCKER_IMAGE=\"$FULL_IMAGE_NAME\""
echo "3. Create Golden AMI using the updated script"
echo ""
echo "Optional: Tag with version"
echo "  docker tag $FULL_IMAGE_NAME ${DOCKER_USERNAME}/${IMAGE_NAME}:v1.0.0"
echo "  docker push ${DOCKER_USERNAME}/${IMAGE_NAME}:v1.0.0"
echo "=========================================="
