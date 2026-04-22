#!/bin/bash
set -e

# Golden AMI Setup Script - Simplified with Pre-built Docker Image
# This version pulls a pre-built image from Docker Hub instead of building on instance
# Compatible with Amazon Linux 2023

echo "=========================================="
echo "Golden AMI Setup - Docker Pull Edition"
echo "=========================================="

# Configuration - UPDATE THIS
DOCKER_IMAGE="praweg/nextjs-blog:latest"  # Your Docker Hub image

echo "Using Docker image: $DOCKER_IMAGE"
echo ""

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

# Add ec2-user to docker group
sudo usermod -aG docker ec2-user

# Install Docker Compose (optional, but useful)
echo "Step 4: Installing Docker Compose..."
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify Docker installation
echo "Step 5: Verifying Docker installation..."
sudo docker --version
sudo docker-compose --version

# Install NGINX for reverse proxy
echo "Step 6: Installing NGINX..."
sudo dnf install -y nginx
sudo systemctl enable nginx

# Create application directory
echo "Step 7: Creating directories..."
sudo mkdir -p /opt/nextjs-app/content/posts
sudo mkdir -p /opt/scripts
sudo chown -R ec2-user:ec2-user /opt/nextjs-app
sudo chown -R ec2-user:ec2-user /opt/scripts

# Pull Docker image from Docker Hub
echo "Step 8: Pulling Docker image from Docker Hub..."
echo "This will take 1-2 minutes..."
sudo docker pull $DOCKER_IMAGE || {
    echo "✗ Failed to pull Docker image"
    echo "  Make sure the image exists and is public"
    echo "  Or login: sudo docker login"
    exit 1
}

# Tag the pulled image as latest for consistency
sudo docker tag $DOCKER_IMAGE nextjs-blog:latest

echo "✓ Docker image pulled successfully"
echo ""

# Show image details
echo "Image details:"
sudo docker images | grep nextjs-blog

# Create NGINX configuration for Docker reverse proxy
echo "Step 9: Configuring NGINX..."
sudo tee /etc/nginx/conf.d/nextjs.conf > /dev/null <<'NGINX_CONF'
upstream nextjs_upstream {
    server localhost:3000;
    keepalive 64;
}

# server {
#     listen 80;
#     server_name _;
server {
  listen 80 default_server;
  listen [::]:80 default_server;
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
echo "Step 10: Testing NGINX configuration..."
sudo nginx -t

# Create deployment script
echo "Step 11: Creating deployment script..."
sudo tee /opt/scripts/deploy-app.sh > /dev/null <<DEPLOY_SCRIPT
#!/bin/bash
set -e

echo "===== Starting Application Deployment at \$(date) ====="

# Optional: Pull latest image version
# Uncomment to enable automatic updates from Docker Hub
# echo "Pulling latest Docker image..."
# sudo docker pull $DOCKER_IMAGE
# sudo docker tag $DOCKER_IMAGE nextjs-blog:latest

# Stop and remove existing container if running
echo "Stopping existing containers..."
sudo docker stop nextjs-blog 2>/dev/null || true
sudo docker rm nextjs-blog 2>/dev/null || true

# Start new container
echo "Starting Next.js container..."
sudo docker run -d \\
    --name nextjs-blog \\
    --restart unless-stopped \\
    -p 3000:3000 \\
    -v /opt/nextjs-app/content:/app/content \\
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

echo "===== Deployment Completed Successfully at \$(date) ====="
DEPLOY_SCRIPT

sudo chmod +x /opt/scripts/deploy-app.sh

echo ""
echo "=========================================="
echo "✓ Golden AMI Setup Complete!"
echo "=========================================="
echo ""
echo "IMPORTANT: Before creating the AMI:"
echo "1. Test the deployment script: sudo /opt/scripts/deploy-app.sh"
echo "2. Verify the application is accessible: curl http://localhost"
echo "3. Clean up any sensitive data or logs"
echo "4. Stop all services:"
echo "   sudo docker stop nextjs-blog"
echo "   sudo systemctl stop nginx"
echo "5. Create AMI from this instance in AWS Console"
echo ""
echo "Docker image used: $DOCKER_IMAGE"
echo "Image size:"
sudo docker images | grep nextjs-blog || echo "No Docker image found"
echo ""
echo "After creating the AMI, use deployment/docker/user-data-docker.sh for the Launch Template"
echo "=========================================="
