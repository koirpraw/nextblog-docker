#!/bin/bash
# Quick fix script for "npm ci Killed" issue on EC2 t2.micro
# Run this on your EC2 instance when npm ci gets killed

set -e

echo "=========================================="
echo "Quick Fix for npm ci OOM (Out of Memory)"
echo "=========================================="
echo ""

# Check if swap already exists
if [ -f /swapfile ]; then
    echo "✓ Swap file already exists"
    sudo swapon /swapfile 2>/dev/null && echo "✓ Swap enabled" || echo "Note: Swap already active"
else
    echo "Creating 1GB swap space..."
    sudo dd if=/dev/zero of=/swapfile bs=128M count=8
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
    echo "✓ Swap space created and enabled"
fi

echo ""
echo "Current memory status:"
free -h
echo ""

# Load NVM
echo "Loading Node.js environment..."
export NVM_DIR="/home/ec2-user/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm use 20

echo "✓ Node.js version: $(node --version)"
echo "✓ npm version: $(npm --version)"
echo ""

# Navigate to app directory
cd /opt/nextjs-app
echo "Working directory: $(pwd)"
echo ""

# Clean up partial installation
if [ -d "node_modules" ]; then
    echo "Removing incomplete node_modules..."
    rm -rf node_modules
    echo "✓ Cleaned up"
fi

if [ -d ".next" ]; then
    echo "Removing old build..."
    rm -rf .next
    echo "✓ Cleaned up"
fi

echo ""
echo "=========================================="
echo "Installing dependencies (2-3 minutes)..."
echo "=========================================="
npm ci --production=false

echo ""
echo "✓ Dependencies installed successfully!"
echo ""
echo "=========================================="
echo "Building application..."
echo "=========================================="
npm run build

echo ""
echo "✓ Build completed successfully!"
echo ""
echo "=========================================="
echo "Restarting application with PM2..."
echo "=========================================="
pm2 delete nextjs-blog 2>/dev/null || true
pm2 start /opt/pm2-ecosystem.config.js
pm2 save

echo ""
echo "✓ Application restarted"
echo ""
pm2 status

echo ""
echo "=========================================="
echo "Testing application..."
echo "=========================================="
sleep 3
curl -s http://localhost:3000 > /dev/null && echo "✓ Next.js responding on port 3000" || echo "✗ Next.js not responding"
curl -s http://localhost/api/health > /dev/null && echo "✓ NGINX health check passing" || echo "✗ NGINX health check failing"

echo ""
echo "=========================================="
echo "✅ Fix complete!"
echo "=========================================="
echo ""
echo "Your application should now be running."
echo "Check status with: pm2 status"
echo "View logs with: pm2 logs nextjs-blog"
echo ""
