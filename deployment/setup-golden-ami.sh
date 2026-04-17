#!/bin/bash
set -e

# This script should be run on your Golden AMI during creation
# Compatible with Amazon Linux 2023

echo "Setting up Golden AMI for Next.js application..."

# Update system
sudo dnf update -y

# Install Git
sudo dnf install -y git

# Install NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc

# Install Node.js
nvm install 20
nvm use 20
nvm alias default 20

# Install PM2 globally
npm install -g pm2

# Install NGINX (Amazon Linux 2023 - nginx is in default repos)
sudo dnf install nginx -y
sudo systemctl enable nginx

# Create application directory
sudo mkdir -p /opt/nextjs-app
sudo chown -R ec2-user:ec2-user /opt/nextjs-app

# Configure NGINX
sudo tee /etc/nginx/conf.d/nextjs-app.conf > /dev/null <<'EOF'
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
EOF

sudo nginx -t

# Create PM2 ecosystem template
sudo tee /opt/pm2-ecosystem.config.js > /dev/null <<'EOF'
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
    },
    error_file: '/var/log/pm2/nextjs-error.log',
    out_file: '/var/log/pm2/nextjs-out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z'
  }]
}
EOF

sudo mkdir -p /var/log/pm2
sudo chown -R ec2-user:ec2-user /var/log/pm2

# Create deployment script
sudo tee /usr/local/bin/deploy-nextjs.sh > /dev/null <<'EOF'
#!/bin/bash
set -e

APP_DIR="/opt/nextjs-app"
REPO_URL="https://github.com/koirpraw/markdown-editor-blog.git"
BRANCH="main"

echo "Starting deployment..."

# Source NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm use 20

# Clone or pull latest code
if [ -d "$APP_DIR/.git" ]; then
    echo "Pulling latest code..."
    cd $APP_DIR
    git fetch origin
    git reset --hard origin/$BRANCH
else
    echo "Cloning repository..."
    git clone -b $BRANCH $REPO_URL $APP_DIR
    cd $APP_DIR
fi

# Install dependencies and build
echo "Installing dependencies..."
npm ci --production=false

echo "Building application..."
npm run build

# Start/Restart with PM2
echo "Starting application with PM2..."
pm2 delete nextjs-blog 2>/dev/null || true
pm2 start /opt/pm2-ecosystem.config.js
pm2 save
pm2 startup systemd -u ec2-user --hp /home/ec2-user

# Ensure NGINX is running
sudo systemctl restart nginx

echo "Deployment complete!"
EOF

sudo chmod +x /usr/local/bin/deploy-nextjs.sh

# Create bootstrap script for user data
sudo tee /opt/user-data-bootstrap.sh > /dev/null <<'EOF'
#!/bin/bash
set -e

# Log all output
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

echo "Starting user data bootstrap at $(date)"

# Source NVM for current session
export NVM_DIR="/home/ec2-user/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Run as ec2-user
sudo -u ec2-user bash << 'EOSU'
source ~/.bashrc
nvm use 20
/usr/local/bin/deploy-nextjs.sh
EOSU

echo "User data bootstrap completed at $(date)"
EOF

sudo chmod +x /opt/user-data-bootstrap.sh

echo "Golden AMI setup complete!"
echo "You can now create an AMI from this instance"
