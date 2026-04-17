# Quick Reference Guide

## Prerequisites Checklist

- [ ] AWS Account with appropriate permissions
- [ ] EC2 Key Pair created
- [ ] GitHub repository URL
- [ ] VPC with public and private subnets in at least 2 AZs
- [ ] NAT Gateway (for private subnets)

## Quick Commands

### Update Repository URL

Update these files with your GitHub repository URL:

```bash
# In deployment/setup-golden-ami.sh (line ~53)
REPO_URL="https://github.com/YOUR_USERNAME/markdown-editor-blog.git"

# In deployment/user-data-full-bootstrap.sh (line ~101)
git clone https://github.com/YOUR_USERNAME/markdown-editor-blog.git .
```

### Create Golden AMI

```bash
# SSH to EC2 instance
ssh -i your-key.pem ec2-user@instance-ip

# Download and run setup script
wget https://raw.githubusercontent.com/YOUR_USERNAME/markdown-editor-blog/main/deployment/setup-golden-ami.sh
chmod +x setup-golden-ami.sh
./setup-golden-ami.sh

# Update repo URL
sudo nano /usr/local/bin/deploy-nextjs.sh

# Test deployment
/usr/local/bin/deploy-nextjs.sh

# Verify
pm2 status
curl http://localhost:3000
curl http://localhost/api/health

# Clean up before AMI creation
pm2 delete all
sudo rm -rf /opt/nextjs-app/.git
sudo rm -rf /opt/nextjs-app/node_modules
sudo rm -rf /opt/nextjs-app/.next
history -c
```

Then create AMI from AWS Console: EC2 → Instances → Actions → Create Image

### User Data for Launch Template (Golden AMI)

```bash
#!/bin/bash
set -e
exec > >(tee -a /var/log/user-data.log)
exec 2>&1
echo "===== User Data Started at $(date) ====="
until ping -c1 github.com &>/dev/null; do sleep 2; done
/opt/user-data-bootstrap.sh
echo "===== User Data Completed at $(date) ====="
```

### User Data for Launch Template (Full Bootstrap)

Use the content from `deployment/user-data-full-bootstrap.sh` after updating the repository URL.

## Security Group Configuration

### ALB Security Group
```
Name: nextjs-alb-sg

Inbound:
- Type: HTTP, Port: 80, Source: 0.0.0.0/0
- Type: HTTPS, Port: 443, Source: 0.0.0.0/0

Outbound:
- Type: HTTP, Port: 80, Destination: sg-xxxxx (instance SG)
```

### Instance Security Group
```
Name: nextjs-instance-sg

Inbound:
- Type: HTTP, Port: 80, Source: sg-xxxxx (ALB SG)
- Type: SSH, Port: 22, Source: YOUR_IP/32

Outbound:
- Type: All traffic, Destination: 0.0.0.0/0
```

## Target Group Settings

```
Name: nextjs-blog-tg
Type: Instances
Protocol: HTTP
Port: 80
Health check path: /api/health
Health check interval: 30 seconds
Healthy threshold: 2
Unhealthy threshold: 3
Timeout: 5 seconds
Success codes: 200
```

## ALB Configuration

```
Name: nextjs-blog-alb
Type: Application Load Balancer
Scheme: Internet-facing
IP address type: IPv4
Subnets: Select 2+ public subnets
Security group: nextjs-alb-sg
Listener: HTTP:80 → Forward to nextjs-blog-tg
```

## Launch Template

```
Name: nextjs-blog-launch-template
AMI: Your Golden AMI ID (ami-xxxxx)
Instance type: t2.micro or t3.micro
Key pair: Your key pair
Security group: nextjs-instance-sg
IAM instance profile: NextjsBlogInstanceRole
User data: See above
```

## Auto Scaling Group

```
Name: nextjs-blog-asg
Launch template: nextjs-blog-launch-template
VPC: Your VPC
Subnets: 2+ private subnets
Load balancing: Attach to nextjs-blog-tg
Health check type: ELB
Health check grace period: 300 seconds
Desired capacity: 2
Minimum capacity: 1
Maximum capacity: 4

Scaling policy:
- Type: Target tracking
- Metric: Average CPU utilization
- Target: 70%
- Instance warmup: 300 seconds
```

## Troubleshooting Commands

```bash
# SSH to instance
ssh -i your-key.pem ec2-user@instance-ip

# Check user data log
sudo tail -f /var/log/user-data.log

# Check PM2 status
pm2 status
pm2 logs nextjs-blog
pm2 describe nextjs-blog

# Check NGINX
sudo systemctl status nginx
sudo nginx -t
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log

# Test locally
curl http://localhost:3000
curl http://localhost:3000/api/health
curl http://localhost/api/health

# Check ports
sudo netstat -tlnp | grep :3000
sudo netstat -tlnp | grep :80

# Check processes
ps aux | grep node
ps aux | grep nginx

# Restart services
pm2 restart nextjs-blog
sudo systemctl restart nginx

# Manual deployment
/usr/local/bin/deploy-nextjs.sh

# Check disk space
df -h

# Check memory
free -h

# Check logs size
du -sh /var/log/pm2/
du -sh /var/log/nginx/
```

## Testing Your Deployment

```bash
# Get ALB DNS name from AWS Console
ALB_DNS="your-alb-dns-name.elb.amazonaws.com"

# Test health check
curl http://$ALB_DNS/api/health

# Test main page
curl http://$ALB_DNS/

# Test admin page
curl http://$ALB_DNS/admin

# Test with verbose output
curl -v http://$ALB_DNS/

# Test from multiple locations
for i in {1..10}; do
  curl -s http://$ALB_DNS/ | grep -o '<title>.*</title>'
done
```

## Monitoring & Metrics

### CloudWatch Metrics to Monitor

```
EC2:
- CPUUtilization
- NetworkIn/NetworkOut
- StatusCheckFailed
- DiskReadBytes/DiskWriteBytes

ALB:
- TargetResponseTime
- RequestCount
- HTTPCode_Target_2XX_Count
- HTTPCode_Target_5XX_Count
- UnHealthyHostCount
- HealthyHostCount

ASG:
- GroupDesiredCapacity
- GroupInServiceInstances
- GroupMinSize
- GroupMaxSize
```

### CloudWatch Alarms to Create

```bash
# Unhealthy hosts
Metric: UnHealthyHostCount
Threshold: >= 1
Duration: 2 consecutive periods

# High CPU
Metric: CPUUtilization
Threshold: >= 80%
Duration: 3 consecutive periods

# High error rate
Metric: HTTPCode_Target_5XX_Count
Threshold: >= 10
Duration: 1 period
```

## Updating Your Application

### Method 1: Terminate Instances (Zero Touch)
```bash
# Push changes to GitHub
git add .
git commit -m "Update application"
git push origin main

# In AWS Console, terminate instances one by one
# ASG will launch new instances that pull latest code
```

### Method 2: Manual Update
```bash
# SSH to each instance
ssh -i your-key.pem ec2-user@instance-ip

# Run deployment script
/usr/local/bin/deploy-nextjs.sh
```

### Method 3: Update AMI
```bash
# 1. Launch instance from current AMI
# 2. SSH and make changes
# 3. Test changes
# 4. Create new AMI
# 5. Update Launch Template with new AMI
# 6. Terminate old instances (ASG launches new ones)
```

## Common Issues & Solutions

### Issue: Instances unhealthy in target group
**Solutions:**
1. Check security group allows ALB → Instance on port 80
2. Verify /api/health endpoint returns 200
3. Check health check grace period (increase to 300s)
4. SSH and test: `curl http://localhost/api/health`

### Issue: User data script fails
**Solutions:**
1. Check log: `sudo tail -f /var/log/user-data.log`
2. Verify GitHub repo URL is correct
3. Ensure instance can reach internet (NAT Gateway)
4. Check IAM role permissions

### Issue: PM2 application crashes
**Solutions:**
1. Check logs: `pm2 logs nextjs-blog`
2. Check memory: `free -h` (add swap if needed)
3. Check disk space: `df -h`
4. Restart: `pm2 restart nextjs-blog`

### Issue: NGINX 502 Bad Gateway
**Solutions:**
1. Check if Next.js is running: `curl http://localhost:3000`
2. Check PM2: `pm2 status`
3. Check NGINX config: `sudo nginx -t`
4. Check NGINX logs: `sudo tail -f /var/log/nginx/error.log`

### Issue: Slow instance launch time
**Solutions:**
1. Use Golden AMI approach instead of full bootstrap
2. Pre-build node_modules in AMI
3. Use faster instance type (t3.micro vs t2.micro)
4. Optimize npm install (use `npm ci`)

## Cost Estimates (us-east-1)

```
t2.micro instances:
- 2 instances 24/7: ~$15/month
- 4 instances 24/7: ~$30/month

Application Load Balancer:
- Basic ALB: ~$16/month
- LCU charges: ~$5-10/month (light traffic)

NAT Gateway (if using private subnets):
- 1 NAT Gateway: ~$32/month
- Data transfer: varies

Total estimated cost: $40-$90/month
(depending on instance count and traffic)

Cost saving tips:
- Use spot instances for non-critical environments
- Scale down during off-hours
- Use t3.micro for better performance per dollar
```

## Next Steps

1. ✅ Create health check endpoint
2. ✅ Set up deployment scripts
3. ✅ Create Golden AMI
4. ✅ Configure security groups
5. ✅ Create target group
6. ✅ Create ALB
7. ✅ Create launch template
8. ✅ Create ASG
9. ✅ Test deployment
10. ⬜ Add custom domain (Route 53)
11. ⬜ Add SSL certificate (ACM)
12. ⬜ Set up CloudWatch alarms
13. ⬜ Configure CloudWatch Logs
14. ⬜ Implement CI/CD pipeline
15. ⬜ Add CloudFront for CDN
