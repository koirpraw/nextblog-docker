#!/bin/bash
set -e

# Redirect output to log
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

echo "===== Starting Full Bootstrap at $(date) ====="

# Update system
sudo yum update -y

# Install Git
sudo yum install -y git

# Install NVM and Node.js
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
export NVM_DIR="/home/ec2-user/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install 20
nvm use 20
nvm alias default 20

# Install PM2 globally
npm install -g pm2

# Install NGINX
sudo amazon-linux-extras install nginx1 -y
sudo systemctl enable nginx

# Create application directory
sudo mkdir -p /opt/nextjs-app
sudo chown -R ec2-user:ec2-user /opt/nextjs-app

# Configure NGINX
sudo tee /etc/nginx/conf.d/nextjs-app.conf > /dev/null <<'NGINX_EOF'
upstream nextjs_upstream {
  server 127.0.0.1:3000;
  keepalive 64;
}

server {
  listen 80;
  server_name _;

  location /health {
    access_log off;
    return 200 "healthy\n";
    add_header Content-Type text/plain;
  }

  location /api/health {
    proxy_pass http://nextjs_upstream;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
  }

  location /_next/static {
    alias /opt/nextjs-app/.next/static;
    expires 365d;
    access_log off;
  }

  location /_next/image {
    proxy_pass http://nextjs_upstream;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host $host;
    proxy_cache_bypass $http_upgrade;
  }

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
  }
}
NGINX_EOF

sudo nginx -t
sudo systemctl start nginx

# Clone and build application
cd /opt/nextjs-app
git clone https://github.com/koirpraw/markdown-editor-blog.git .

# Wait for network
until ping -c1 github.com &>/dev/null; do
    echo "Waiting for network..."
    sleep 2
done

# Install dependencies and build
npm ci --production=false
npm run build

# Create PM2 ecosystem config
cat > /opt/nextjs-app/ecosystem.config.js <<'PM2_EOF'
module.exports = {
  apps: [{
    name: 'nextjs-blog',
    script: 'npm',
    args: 'start',
    cwd: '/opt/nextjs-app',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '800M',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    }
  }]
}
PM2_EOF

# Start application with PM2
pm2 start ecosystem.config.js
pm2 save
pm2 startup systemd -u ec2-user --hp /home/ec2-user

echo "===== Bootstrap Completed at $(date) ====="
