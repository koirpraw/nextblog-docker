# Docker Deployment Quick Reference

Quick commands and tips for deploying the Next.js blog with Docker, ASG, and ALB.

## 🚀 Quick Start

```bash
# 1. Create Golden AMI (on EC2 instance)
ssh -i ~/.ssh/sandbox-ec2-key.pem ec2-user@<instance-ip>
git clone https://github.com/YOUR_USERNAME/nextblog-docker.git
cd nextblog-docker
sudo ./deployment/setup-golden-ami-docker.sh

# 2. Create AMI from instance (on your local machine)
aws ec2 create-image \
    --region us-east-1 \
    --instance-id <instance-id> \
    --name "nextjs-blog-golden-ami-v1" \
    --description "Next.js blog with Docker pre-built"

# 3. Set up infrastructure (update AMI_ID first!)
cd deployment
chmod +x setup-aws-infrastructure.sh
./setup-aws-infrastructure.sh
```

## 📁 File Reference

### Deployment Scripts

| File | Purpose | When to Use |
|------|---------|-------------|
| `setup-golden-ami-docker.sh` | Creates Golden AMI with Docker and pre-built image | Run once on a fresh EC2 instance |
| `user-data-docker.sh` | Starts application on ASG instances | Used in Launch Template |
| `setup-aws-infrastructure.sh` | Creates ALB, Target Group, Launch Template, ASG | Run once from your local machine |
| `DOCKER-DEPLOYMENT-GUIDE.md` | Complete step-by-step guide | Read this first! |

### Configuration Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage Docker build for Next.js |
| `next.config.ts` | Next.js configuration (standalone output enabled) |
| `.dockerignore` | Files to exclude from Docker build |

## 🔧 Common Commands

### Monitoring

```bash
# Check ASG status
aws autoscaling describe-auto-scaling-groups \
    --region us-east-1 \
    --auto-scaling-group-names nextjs-blog-asg

# Check target health
aws elbv2 describe-target-health \
    --region us-east-1 \
    --target-group-arn <target-group-arn>

# Get ALB DNS
aws elbv2 describe-load-balancers \
    --region us-east-1 \
    --names nextjs-blog-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text

# List running instances
aws ec2 describe-instances \
    --region us-east-1 \
    --filters "Name=tag:Name,Values=nextjs-blog-asg" "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress,State.Name]' \
    --output table
```

### Debugging on Instance

```bash
# SSH into instance
ssh -i ~/.ssh/sandbox-ec2-key.pem ec2-user@<instance-ip>

# Check user-data logs
sudo tail -f /var/log/user-data.log

# Check Docker container
sudo docker ps
sudo docker logs nextjs-blog --follow

# Check NGINX
sudo systemctl status nginx
sudo tail -f /var/log/nginx/nextjs-error.log

# Test application locally
curl http://localhost:3000/api/health  # Direct to container
curl http://localhost/api/health       # Through NGINX

# Restart services
sudo docker restart nextjs-blog
sudo systemctl restart nginx
```

### Scaling

```bash
# Scale up
aws autoscaling set-desired-capacity \
    --region us-east-1 \
    --auto-scaling-group-name nextjs-blog-asg \
    --desired-capacity 3

# Scale down
aws autoscaling set-desired-capacity \
    --region us-east-1 \
    --auto-scaling-group-name nextjs-blog-asg \
    --desired-capacity 1

# Update min/max
aws autoscaling update-auto-scaling-group \
    --region us-east-1 \
    --auto-scaling-group-name nextjs-blog-asg \
    --min-size 1 \
    --max-size 5
```

### Updates

```bash
# To deploy code changes:
# 1. Create new Golden AMI with updated code
# 2. Create new Launch Template version
# 3. Perform rolling update

# Create new Launch Template version
aws ec2 create-launch-template-version \
    --region us-east-1 \
    --launch-template-name nextjs-blog-lt \
    --source-version '$Latest' \
    --launch-template-data '{"ImageId":"<new-ami-id>"}'

# Update ASG to use new version
aws autoscaling update-auto-scaling-group \
    --region us-east-1 \
    --auto-scaling-group-name nextjs-blog-asg \
    --launch-template LaunchTemplateName=nextjs-blog-lt,Version='$Latest'

# Trigger rolling update by terminating instances (they'll be replaced with new version)
# ASG will maintain desired capacity
```

## 🐛 Troubleshooting Quick Fixes

### Targets not becoming healthy

```bash
# Check health endpoint
curl http://localhost/api/health

# If fails, restart services
sudo docker restart nextjs-blog
sleep 10
sudo systemctl restart nginx

# Check Docker logs
sudo docker logs nextjs-blog --tail 100
```

### Container won't start

```bash
# Check if image exists
sudo docker images | grep nextjs-blog

# If missing, rebuild
cd /opt/nextjs-app/app
sudo docker build -t nextjs-blog:latest .

# Check for port conflicts
sudo netstat -tlnp | grep 3000

# Force restart
sudo docker stop nextjs-blog || true
sudo docker rm nextjs-blog || true
sudo /opt/scripts/deploy-app.sh
```

### NGINX errors

```bash
# Test configuration
sudo nginx -t

# View error log
sudo tail -100 /var/log/nginx/nextjs-error.log

# Restart NGINX
sudo systemctl restart nginx
```

## 💾 Testing Golden AMI Before Creating

```bash
# After running setup-golden-ami-docker.sh, test everything:

# 1. Test Docker image exists
sudo docker images | grep nextjs-blog

# 2. Run deployment script
sudo /opt/scripts/deploy-app.sh

# 3. Wait for services
sleep 30

# 4. Test endpoints
curl http://localhost:3000/api/health  # Should return {"status":"healthy"}
curl http://localhost/api/health       # Should return same through NGINX
curl http://localhost                  # Should return HTML

# 5. Check Docker container
sudo docker ps | grep nextjs-blog

# 6. Check NGINX
sudo systemctl status nginx

# All checks pass? Ready to create AMI!
```

## 📊 Expected Timelines

| Phase | Duration | Notes |
|-------|----------|-------|
| Golden AMI creation | 10-15 min | One-time setup |
| AMI snapshot | 2-5 min | AWS processing |
| Infrastructure setup | 2-3 min | ALB, Target Group, ASG creation |
| Instance launch from Golden AMI | 1 min | EC2 startup |
| User-data execution | 2-3 min | Docker start + health checks |
| **Total to production** | **15-20 min** | First deployment |
| **New instance launch** | **3-4 min** | Subsequent scaling |

## 📏 Resource Sizes

| Resource | Size | Notes |
|----------|------|-------|
| Docker image | ~350-400 MB | Multi-stage build optimized |
| Golden AMI snapshot | ~2-3 GB | Base OS + Docker + image |
| EBS volume per instance | 20 GB | Can reduce to 10 GB if needed |
| Memory usage (container) | ~150-200 MB | Next.js production |
| Memory usage (total) | ~400-500 MB | Including OS, Docker, NGINX |

## 🎯 Recommended Settings for t3.micro

```bash
# ASG Configuration (for t3.micro - 1GB RAM, 2 vCPU)
Min Size: 1
Max Size: 3
Desired: 2

# Scaling Policy
CPU Target: 50%
Scale-up cooldown: 300s
Scale-down cooldown: 300s

# Health Check
Grace period: 300s (5 minutes)
Health check type: ELB
Check interval: 30s
Timeout: 5s
Healthy threshold: 2
Unhealthy threshold: 3

# Connection Draining
Timeout: 30s
```

## 🔐 Security Checklist

- ✅ Security group allows only port 80 (from ALB) and 22 (from your IP)
- ✅ No hardcoded secrets in code or user-data
- ✅ IAM instance profile with minimal permissions
- ✅ NGINX security headers configured
- ✅ Docker container runs as non-root user
- ✅ Regular updates via new Golden AMI versions

## 💰 Cost Calculator

**Monthly cost in us-east-1:**

```
2x t3.micro on-demand:
  2 × $0.0104/hr × 730 hrs = $15.18

ALB:
  Base: $16.20/month
  Data: ~$0.008/GB (varies with traffic)

EBS (2x 20GB gp3):
  2 × 20GB × $0.08/GB = $3.20

Total: ~$35/month (without data transfer)

With Spot Instances (70% discount):
  2x t3.micro spot: ~$4.50
  ALB: $16.20
  EBS: $3.20
  Total: ~$24/month
```

## 📚 Related Documentation

- Full guide: [DOCKER-DEPLOYMENT-GUIDE.md](DOCKER-DEPLOYMENT-GUIDE.md)
- Troubleshooting: [../TROUBLESHOOTING.md](../TROUBLESHOOTING.md)
- Main README: [../../README.md](../../README.md)

---

**Need help?** Check the full deployment guide or troubleshooting docs!
