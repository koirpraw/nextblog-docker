#!/bin/bash
set -e

# Golden AMI Setup Script for Docker-based Next.js Deployment
# Compatible with Amazon Linux 2023
# This script prepares an EC2 instance to become a Golden AMI

echo "=========================================="
echo "Golden AMI Setup - Docker Edition"
echo "=========================================="

# Update system
echo "Step 1: Updating system packages..."
sudo dnf update -y

# Install Docker
echo "Step 2: Installing Docker..."
sudo dnf install docker -y

# Start and enable Docker service
echo "Step 3: Configuring Docker service..."
sudo systemctl start docker
sudo systemctl enable docker

# Add ec2-user to docker group (requires re-login to take effect)
sudo usermod -aG docker ec2-user

# Install Docker Compose
echo "Step 4: Installing Docker Compose..."
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify Docker installation
echo "Step 5: Verifying Docker installation..."
sudo docker --version
sudo docker-compose --version

# Install Git
echo "Step 6: Installing Git..."
sudo dnf install -y git

# Install NGINX for reverse proxy
echo "Step 7: Installing NGINX..."
sudo dnf install -y nginx
sudo systemctl enable nginx

# Create application directory
echo "Step 8: Creating application directory..."
sudo mkdir -p /opt/nextjs-app
sudo chown -R ec2-user:ec2-user /opt/nextjs-app

# Create deployment script directory
sudo mkdir -p /opt/scripts
sudo chown -R ec2-user:ec2-user /opt/scripts

# Download application code (UPDATE THIS URL WITH YOUR REPO)
echo "Step 9: Cloning application repository..."
REPO_URL="https://github.com/koirpraw/nextblog-docker.git"
cd /opt/nextjs-app
git clone $REPO_URL app || echo "Failed to clone repository - update REPO_URL in script"

# Build Docker image (this is the time-consuming part that we pre-do in Golden AMI)
echo "Step 10: Building Docker image (this will take 5-10 minutes)..."
if [ -d "/opt/nextjs-app/app" ]; then
    cd /opt/nextjs-app/app
    # Run docker build with sudo since ec2-user group change requires re-login
    sudo docker build -t nextjs-blog:latest .
    echo "✓ Docker image built successfully"
else
    echo "⚠ Application directory not found - skipping Docker build"
    echo "  You'll need to build the image manually or fix the REPO_URL"
fi

# Create NGINX configuration for Docker reverse proxy
echo "Step 11: Configuring NGINX..."
sudo tee /etc/nginx/conf.d/nextjs.conf > /dev/null <<'NGINX_CONF'
upstream nextjs_upstream {
    server localhost:3000;
    keepalive 64;
}

server {
    listen 80;
    server_name _;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;

    # Client body size
    client_max_body_size 10M;

    # Logging
    access_log /var/log/nginx/nextjs-access.log;
    error_log /var/log/nginx/nextjs-error.log;

    # Health check endpoint for ALB
    location /api/health {
        proxy_pass http://nextjs_upstream;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Short timeout for health checks
        proxy_connect_timeout 5s;
        proxy_send_timeout 10s;
        proxy_read_timeout 10s;
    }

    # Next.js application
    location / {
        proxy_pass http://nextjs_upstream;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Increase timeouts for Next.js
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Static files caching
    location /_next/static {
        proxy_pass http://nextjs_upstream;
        proxy_cache_valid 200 60m;
        add_header Cache-Control "public, max-age=3600, immutable";
    }
}
NGINX_CONF

# Remove default NGINX config if exists
sudo rm -f /etc/nginx/conf.d/default.conf

# Test NGINX configuration
echo "Step 12: Testing NGINX configuration..."
sudo nginx -t

# Create deployment bootstrap script
echo "Step 13: Creating deployment bootstrap script..."
sudo tee /opt/scripts/deploy-app.sh > /dev/null <<'DEPLOY_SCRIPT'
#!/bin/bash
set -e

echo "===== Starting Application Deployment at $(date) ====="

# Navigate to app directory
cd /opt/nextjs-app/app

# Pull latest changes (optional - comment out if you want to use Golden AMI code only)
# git pull origin main

# Stop and remove existing container if running
echo "Stopping existing containers..."
sudo docker stop nextjs-blog 2>/dev/null || true
sudo docker rm nextjs-blog 2>/dev/null || true

# Start new container
echo "Starting Next.js container..."
sudo docker run -d \
    --name nextjs-blog \
    --restart unless-stopped \
    -p 80:3000 \
    -v /opt/nextjs-app/content:/app/content \
    nextjs-blog:latest

# Wait for container to be healthy
echo "Waiting for Next.js to start..."
sleep 10

# Verify container is running
if sudo docker ps | grep -q nextjs-blog; then
    echo "✓ Container is running"
else
    echo "✗ Container failed to start"
    sudo docker logs nextjs-blog
    exit 1
fi

# Start NGINX
echo "Starting NGINX..."
sudo systemctl restart nginx

# Wait for services
sleep 5

# Health checks
echo "Running health checks..."

# Check Next.js directly
if curl -f http://localhost:3000/api/health > /dev/null 2>&1; then
    echo "✓ Next.js is responding on port 3000"
else
    echo "✗ Next.js health check failed"
    exit 1
fi

# Check NGINX
if curl -f http://localhost/api/health > /dev/null 2>&1; then
    echo "✓ NGINX is proxying correctly"
else
    echo "✗ NGINX health check failed"
    exit 1
fi

echo "===== Deployment Completed Successfully at $(date) ====="
DEPLOY_SCRIPT

sudo chmod +x /opt/scripts/deploy-app.sh

# Create content directory for markdown posts
echo "Step 14: Creating content directory..."
sudo mkdir -p /opt/nextjs-app/content/posts
sudo chown -R ec2-user:ec2-user /opt/nextjs-app/content

# Copy sample posts if they exist
if [ -d "/opt/nextjs-app/app/content/posts" ]; then
    cp -r /opt/nextjs-app/app/content/posts/* /opt/nextjs-app/content/posts/ 2>/dev/null || true
fi

echo ""
echo "=========================================="
echo "✓ Golden AMI Setup Complete!"
echo "=========================================="
echo ""
echo "IMPORTANT: Before creating the AMI:"
echo "1. Test the deployment script: sudo /opt/scripts/deploy-app.sh"
echo "2. Verify the application is accessible: curl http://localhost"
echo "3. Clean up any sensitive data or logs"
echo "4. Stop all services: sudo systemctl stop nginx && sudo docker stop nextjs-blog"
echo "5. Create AMI from this instance in AWS Console"
echo ""
echo "Docker image size:"
sudo docker images | grep nextjs-blog || echo "No Docker image found"
echo ""
echo "After creating the AMI, use deployment/docker/user-data-docker.sh for the Launch Template"
echo "=========================================="
