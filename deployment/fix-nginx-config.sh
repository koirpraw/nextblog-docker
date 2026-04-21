#!/bin/bash
# Fix NGINX configuration for Next.js on Amazon Linux 2023
# Run this on your EC2 instance if you can't access the app via public IP

set -e

echo "=========================================="
echo "Fixing NGINX Configuration"
echo "=========================================="
echo ""

# Backup existing configs
echo "Backing up existing NGINX configuration..."
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup.$(date +%Y%m%d_%H%M%S)
if [ -f /etc/nginx/conf.d/nextjs-app.conf ]; then
    sudo cp /etc/nginx/conf.d/nextjs-app.conf /etc/nginx/conf.d/nextjs-app.conf.backup.$(date +%Y%m%d_%H%M%S)
fi
echo "✓ Backup created"
echo ""

# Create clean main NGINX config
echo "Creating clean main NGINX configuration..."
sudo tee /etc/nginx/nginx.conf > /dev/null <<'NGINX_MAIN'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    keepalive_timeout   65;
    types_hash_max_size 4096;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Load modular configuration files from the /etc/nginx/conf.d directory.
    include /etc/nginx/conf.d/*.conf;
}
NGINX_MAIN

echo "✓ Main config created"
echo ""

# Remove any default.conf that might conflict
if [ -f /etc/nginx/conf.d/default.conf ]; then
    echo "Removing default.conf..."
    sudo mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.disabled
    echo "✓ Removed"
fi
echo ""

# Create Next.js app configuration
echo "Creating Next.js app configuration..."
sudo tee /etc/nginx/conf.d/nextjs-app.conf > /dev/null <<'NEXTJS_CONF'
upstream nextjs_upstream {
  server 127.0.0.1:3000;
  keepalive 64;
}

server {
  listen 80 default_server;
  listen [::]:80 default_server;
  server_name _;

  # Increase timeouts for slower responses
  proxy_connect_timeout 60s;
  proxy_send_timeout 60s;
  proxy_read_timeout 60s;

  # Basic health check (NGINX level)
  location /health {
    access_log off;
    return 200 "healthy\n";
    add_header Content-Type text/plain;
  }

  # Next.js health check
  location /api/health {
    proxy_pass http://nextjs_upstream;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }

  # Next.js static files (cache for performance)
  location /_next/static {
    alias /opt/nextjs-app/.next/static;
    expires 365d;
    access_log off;
    add_header Cache-Control "public, immutable";
  }

  # Next.js image optimization
  location /_next/image {
    proxy_pass http://nextjs_upstream;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_cache_bypass $http_upgrade;
  }

  # Public static files
  location /public {
    alias /opt/nextjs-app/public;
    expires 7d;
    access_log off;
  }

  # Proxy all other requests to Next.js
  location / {
    proxy_pass http://nextjs_upstream;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_cache_bypass $http_upgrade;
    
    # Disable buffering for better real-time response
    proxy_buffering off;
  }
}
NEXTJS_CONF

echo "✓ Next.js config created"
echo ""

# Test configuration
echo "Testing NGINX configuration..."
sudo nginx -t

if [ $? -eq 0 ]; then
    echo "✓ Configuration is valid"
    echo ""
    
    # Restart NGINX
    echo "Restarting NGINX..."
    sudo systemctl restart nginx
    sudo systemctl enable nginx
    echo "✓ NGINX restarted"
    echo ""
    
    # Wait a moment for NGINX to start
    sleep 2
    
    # Test locally
    echo "=========================================="
    echo "Testing Configuration"
    echo "=========================================="
    echo ""
    
    echo "1. Testing NGINX health check..."
    if curl -s http://localhost/health > /dev/null; then
        echo "   ✓ NGINX health check: OK"
    else
        echo "   ✗ NGINX health check: FAILED"
    fi
    
    echo "2. Testing Next.js via NGINX..."
    if curl -s http://localhost/ > /dev/null; then
        echo "   ✓ Next.js via NGINX: OK"
    else
        echo "   ✗ Next.js via NGINX: FAILED"
    fi
    
    echo "3. Testing Next.js health endpoint..."
    if curl -s http://localhost/api/health > /dev/null; then
        echo "   ✓ Next.js health endpoint: OK"
    else
        echo "   ✗ Next.js health endpoint: FAILED"
    fi
    
    echo ""
    echo "=========================================="
    echo "✅ Configuration Complete!"
    echo "=========================================="
    echo ""
    echo "Your app should now be accessible at:"
    echo "  http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo 'YOUR-PUBLIC-IP')"
    echo ""
    echo "NGINX Status:"
    sudo systemctl status nginx --no-pager | head -5
    echo ""
    echo "If you still can't access from public IP, check:"
    echo "1. Security Group allows HTTP (port 80) from 0.0.0.0/0"
    echo "2. Instance has a public IP assigned"
    echo "3. PM2 status: pm2 status"
    echo ""
else
    echo "✗ Configuration test failed!"
    echo "Check the error messages above"
    exit 1
fi
