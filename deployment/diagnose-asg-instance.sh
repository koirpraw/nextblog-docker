#!/bin/bash
# Diagnostic script to understand why ASG instances aren't running the app

echo "=========================================="
echo "ASG Instance Diagnostic Report"
echo "=========================================="
echo ""

echo "1. Instance Metadata"
echo "   Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
echo "   Launch Time: $(curl -s http://169.254.169.254/latest/meta-data/ami-launch-index)"
echo ""

echo "2. User Data Script"
echo "   Checking if user data exists..."
USER_DATA=$(curl -s http://169.254.169.254/latest/user-data)
if [ -n "$USER_DATA" ]; then
    echo "   ✓ User data present"
    echo "   First 10 lines:"
    echo "$USER_DATA" | head -10
else
    echo "   ✗ No user data found!"
fi
echo ""

echo "3. User Data Execution Logs"
if [ -f /var/log/user-data.log ]; then
    echo "   ✓ User data log exists"
    echo "   Last 20 lines:"
    sudo tail -20 /var/log/user-data.log
else
    echo "   ✗ User data log not found - script may not have run!"
    echo "   Checking cloud-init logs instead..."
    sudo tail -30 /var/log/cloud-init-output.log 2>/dev/null || echo "   No cloud-init logs found"
fi
echo ""

echo "4. Bootstrap Script"
if [ -f /opt/user-data-bootstrap.sh ]; then
    echo "   ✓ Bootstrap script exists"
    ls -la /opt/user-data-bootstrap.sh
else
    echo "   ✗ Bootstrap script missing!"
fi
echo ""

echo "5. Deployment Script"
if [ -f /usr/local/bin/deploy-nextjs.sh ]; then
    echo "   ✓ Deployment script exists"
    ls -la /usr/local/bin/deploy-nextjs.sh
else
    echo "   ✗ Deployment script missing!"
fi
echo ""

echo "6. Node.js Environment"
echo "   Checking if NVM is installed..."
if [ -d "/home/ec2-user/.nvm" ]; then
    echo "   ✓ NVM directory exists"
    source /home/ec2-user/.nvm/nvm.sh 2>/dev/null && echo "   ✓ NVM loaded" || echo "   ✗ NVM failed to load"
    nvm --version 2>/dev/null && echo "   ✓ NVM version: $(nvm --version)" || echo "   ✗ NVM command not found"
    node --version 2>/dev/null && echo "   ✓ Node version: $(node --version)" || echo "   ✗ Node not available"
    npm --version 2>/dev/null && echo "   ✓ npm version: $(npm --version)" || echo "   ✗ npm not available"
else
    echo "   ✗ NVM not installed!"
fi
echo ""

echo "7. Application Directory"
if [ -d /opt/nextjs-app ]; then
    echo "   ✓ App directory exists"
    echo "   Contents:"
    ls -la /opt/nextjs-app/ | head -15
    
    if [ -d /opt/nextjs-app/.git ]; then
        echo "   ✓ Git repository present"
        cd /opt/nextjs-app
        echo "   Current branch: $(git branch --show-current 2>/dev/null || echo 'Unknown')"
        echo "   Last commit: $(git log -1 --oneline 2>/dev/null || echo 'Unknown')"
    else
        echo "   ✗ No Git repository"
    fi
    
    if [ -d /opt/nextjs-app/node_modules ]; then
        echo "   ✓ node_modules exists ($(ls /opt/nextjs-app/node_modules | wc -l) packages)"
    else
        echo "   ✗ node_modules missing - dependencies not installed!"
    fi
    
    if [ -d /opt/nextjs-app/.next ]; then
        echo "   ✓ .next build directory exists"
    else
        echo "   ✗ .next missing - app not built!"
    fi
else
    echo "   ✗ App directory doesn't exist!"
fi
echo ""

echo "8. PM2 Process Manager"
pm2 --version &>/dev/null && echo "   ✓ PM2 installed: $(pm2 --version)" || echo "   ✗ PM2 not installed"
echo "   PM2 Status:"
pm2 status 2>/dev/null || echo "   PM2 not running or no processes"
echo ""

echo "9. NGINX Status"
sudo systemctl is-active nginx &>/dev/null && echo "   ✓ NGINX is running" || echo "   ✗ NGINX is not running"
sudo nginx -t &>/dev/null && echo "   ✓ NGINX config is valid" || echo "   ✗ NGINX config has errors"
if [ -f /etc/nginx/conf.d/nextjs-app.conf ]; then
    echo "   ✓ Next.js NGINX config exists"
else
    echo "   ✗ Next.js NGINX config missing"
fi
echo ""

echo "10. Network Tests"
echo "   Testing Next.js directly (port 3000):"
curl -s -o /dev/null -w "   HTTP Status: %{http_code}\n" http://localhost:3000 || echo "   ✗ Failed to connect"

echo "   Testing via NGINX (port 80):"
curl -s -o /dev/null -w "   HTTP Status: %{http_code}\n" http://localhost || echo "   ✗ Failed to connect"

echo "   Testing health endpoint:"
curl -s -o /dev/null -w "   HTTP Status: %{http_code}\n" http://localhost/api/health || echo "   ✗ Failed to connect"
echo ""

echo "11. Swap Space"
echo "   Memory status:"
free -h | head -2
if [ -f /swapfile ]; then
    echo "   ✓ Swap file exists"
    swapon --show
else
    echo "   ✗ No swap file"
fi
echo ""

echo "12. Recent System Logs"
echo "   Last 10 system messages:"
sudo journalctl -n 10 --no-pager
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""

# Determine likely issue
if [ ! -f /var/log/user-data.log ]; then
    echo "❌ ISSUE: User data script did not run!"
    echo "   → Check launch template user data configuration"
elif ! grep -q "Deployment complete" /var/log/user-data.log 2>/dev/null; then
    echo "❌ ISSUE: Deployment script did not complete successfully"
    echo "   → Check /var/log/user-data.log for errors"
elif [ ! -d /opt/nextjs-app/node_modules ]; then
    echo "❌ ISSUE: Dependencies not installed"
    echo "   → npm ci likely failed or wasn't run"
elif [ ! -d /opt/nextjs-app/.next ]; then
    echo "❌ ISSUE: Application not built"
    echo "   → npm run build likely failed"
elif ! pm2 status 2>/dev/null | grep -q "online"; then
    echo "❌ ISSUE: PM2 not running the app"
    echo "   → PM2 process not started or crashed"
else
    echo "✅ Setup looks correct - check NGINX logs for issues"
    echo "   → sudo tail -f /var/log/nginx/error.log"
fi

echo ""
echo "To manually fix, try running:"
echo "  source ~/.nvm/nvm.sh && nvm use 20"
echo "  /usr/local/bin/deploy-nextjs.sh"
echo ""
