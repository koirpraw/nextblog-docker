#!/bin/bash
set -e

# User Data Script for Launch Template (Docker-based)
# This script runs on EC2 instances launched from the Golden AMI
# It's optimized for fast startup since Docker image is pre-built

# Redirect all output to log file
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

echo "===== User Data Execution Started at $(date) ====="
echo "Instance ID: $(ec2-metadata --instance-id | cut -d ' ' -f 2)"
echo "Availability Zone: $(ec2-metadata --availability-zone | cut -d ' ' -f 2)"

# Wait for cloud-init to complete
echo "Waiting for cloud-init to complete..."
cloud-init status --wait || true

# Ensure Docker is running
echo "Ensuring Docker service is running..."
sudo systemctl start docker
sudo systemctl enable docker

# Wait for Docker daemon
echo "Waiting for Docker daemon..."
timeout 30 bash -c 'until sudo docker info > /dev/null 2>&1; do sleep 2; done' || {
    echo "✗ Docker daemon failed to start"
    exit 1
}

# Optional: Pull latest code (comment out if you want static Golden AMI deployment)
# echo "Pulling latest application code..."
# cd /opt/nextjs-app/app
# git pull origin main || echo "⚠ Git pull failed, using existing code"
# 
# # Rebuild Docker image if code changed
# echo "Rebuilding Docker image..."
# sudo docker build -t nextjs-blog:latest . || {
#     echo "✗ Docker build failed"
#     exit 1
# }

# Run deployment script (from Golden AMI)
echo "Running deployment script..."
sudo /opt/scripts/deploy-app.sh || {
    echo "✗ Deployment script failed"
    exit 1
}

# Final verification
echo "Final verification..."
sleep 5

# Check if application is responding
if curl -f http://localhost/api/health > /dev/null 2>&1; then
    echo "✓ Application is healthy and ready"
else
    echo "✗ Application health check failed"
    echo "Container logs:"
    sudo docker logs nextjs-blog --tail 50
    echo "NGINX logs:"
    sudo tail -50 /var/log/nginx/nextjs-error.log
    exit 1
fi

echo "===== User Data Execution Completed Successfully at $(date) ====="
echo "Instance is ready to serve traffic"
