#!/bin/bash
set -e

# This user data script is used with the Golden AMI
# It only needs to pull the latest code and start the application

# Redirect all output to log file
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

echo "===== User Data Execution Started at $(date) ====="

# Wait for network to be available
echo "Waiting for network connectivity..."
until ping -c1 github.com &>/dev/null; do
    sleep 2
done
echo "Network is ready"

# Execute the deployment script
echo "Running deployment script..."
/opt/user-data-bootstrap.sh

# Verify services are running
echo "Verifying services..."
sleep 10

# Check if Next.js is responding
if curl -f http://localhost:3000 > /dev/null 2>&1; then
    echo "✓ Next.js application is running"
else
    echo "✗ Next.js application failed to start"
    exit 1
fi

# Check if NGINX is responding
if curl -f http://localhost/api/health > /dev/null 2>&1; then
    echo "✓ NGINX is serving traffic"
else
    echo "✗ NGINX health check failed"
    exit 1
fi

echo "===== User Data Execution Completed Successfully at $(date) ====="
