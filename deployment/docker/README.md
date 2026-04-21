# Docker-based ASG + ALB Deployment

This directory contains all scripts and documentation for deploying the Next.js blog application on AWS using Docker containers in an Auto Scaling Group behind an Application Load Balancer.

## 📁 Directory Contents

### Documentation
- **[STEP-BY-STEP.md](STEP-BY-STEP.md)** - Start here! Complete walkthrough with actionable steps
- **[DOCKER-DEPLOYMENT-GUIDE.md](DOCKER-DEPLOYMENT-GUIDE.md)** - Comprehensive reference guide
- **[DOCKER-QUICK-REFERENCE.md](DOCKER-QUICK-REFERENCE.md)** - Quick commands and troubleshooting

### Scripts
- **[setup-golden-ami-docker.sh](setup-golden-ami-docker.sh)** - Creates Golden AMI with Docker and pre-built image
- **[user-data-docker.sh](user-data-docker.sh)** - User data script for Launch Template (starts application on boot)
- **[setup-aws-infrastructure.sh](setup-aws-infrastructure.sh)** - Automated AWS infrastructure setup (ALB, Target Group, Launch Template, ASG)

## 🚀 Quick Start

```bash
# 1. Read the step-by-step guide
cat STEP-BY-STEP.md

# 2. Update repository URL in setup-golden-ami-docker.sh (line 75)
# 3. Create Golden AMI following STEP-BY-STEP.md Phase 1
# 4. Update AMI ID in setup-aws-infrastructure.sh (line 11)
# 5. Run infrastructure setup
./setup-aws-infrastructure.sh
```

## 🏗️ Architecture

```
Internet
    ↓
Application Load Balancer (ALB)
    ↓
Target Group (Health Check: /api/health)
    ↓
Auto Scaling Group (Min: 1, Max: 3, Desired: 2)
    ↓
EC2 Instances (Golden AMI with Docker)
    ↓
NGINX (Port 80) → Docker Container (Port 3000) → Next.js App
```

## ⚡ Why Docker + Golden AMI?

- **Fast Launch Time**: ~2-3 minutes (vs ~10 minutes with full bootstrap)
- **Consistent Environment**: Docker ensures same runtime everywhere
- **Easy Updates**: Build new AMI → Update Launch Template → Rolling deployment
- **Smaller Codebase**: No PM2, no complex setup scripts

## 📊 Deployment Phases

### Phase 1: Create Golden AMI (One-time, 15-20 min)
1. Launch fresh EC2 instance
2. Run `setup-golden-ami-docker.sh`
3. Create AMI from instance

**Result**: AMI with Docker installed and application image pre-built

### Phase 2: Deploy Infrastructure (5-10 min)
1. Update AMI ID in `setup-aws-infrastructure.sh`
2. Run script to create ALB + ASG

**Result**: Production-ready auto-scaling infrastructure

### Phase 3: Verify & Monitor (3-5 min)
1. Watch instances launch
2. Check target health
3. Access application via ALB DNS

**Result**: Application serving traffic with auto-scaling enabled

## 🔧 Key Configuration

### Instance Launch Flow
1. ASG launches instance from Golden AMI
2. `user-data-docker.sh` executes
3. Script starts Docker container
4. NGINX reverse proxy configured
5. Health checks pass
6. Instance receives traffic from ALB

### Health Checks
- **Endpoint**: `/api/health`
- **Expected Response**: `{"status":"healthy"}`
- **Interval**: 30 seconds
- **Healthy Threshold**: 2 consecutive successes
- **Unhealthy Threshold**: 3 consecutive failures

### Auto Scaling
- **Min Size**: 1 instance
- **Max Size**: 3 instances
- **Desired**: 2 instances
- **Scaling Trigger**: CPU > 50%
- **Cooldown**: 300 seconds

## 💰 Cost Estimate (us-east-1)

**With On-Demand Instances:**
- 2x t3.micro: ~$15/month
- ALB: ~$16/month
- EBS: ~$3/month
- **Total**: ~$34/month

**With Spot Instances (70% savings):**
- 2x t3.micro Spot: ~$4.50/month
- ALB: ~$16/month
- EBS: ~$3/month
- **Total**: ~$24/month

## 🐛 Troubleshooting

### Targets not becoming healthy?
```bash
# SSH into instance
ssh -i ~/.ssh/sandbox-ec2-key.pem ec2-user@<instance-ip>

# Check logs
sudo tail -f /var/log/user-data.log
sudo docker logs nextjs-blog --follow
sudo tail -f /var/log/nginx/nextjs-error.log

# Test locally
curl http://localhost/api/health
```

### Need to rebuild image?
```bash
cd /opt/nextjs-app/app
sudo docker build -t nextjs-blog:latest .
sudo docker restart nextjs-blog
```

For more troubleshooting, see [../TROUBLESHOOTING.md](../TROUBLESHOOTING.md)

## 📝 Updating Your Application

To deploy code changes:

1. **Create new Golden AMI**
   ```bash
   # On fresh EC2 instance with updated code
   sudo ./setup-golden-ami-docker.sh
   # Create new AMI
   ```

2. **Update Launch Template**
   ```bash
   aws ec2 create-launch-template-version \
       --region us-east-1 \
       --launch-template-name nextjs-blog-lt \
       --source-version '$Latest' \
       --launch-template-data '{"ImageId":"<new-ami-id>"}'
   ```

3. **Trigger Rolling Update**
   ```bash
   # ASG will replace instances one by one
   aws autoscaling start-instance-refresh \
       --region us-east-1 \
       --auto-scaling-group-name nextjs-blog-asg
   ```

## 🔒 Security Notes

- Security group limits port 80 to ALB only
- Docker container runs as non-root user (`nextjs`)
- NGINX includes security headers
- No secrets in user-data or code
- Use IAM instance profiles for AWS access

## 📚 Related Documentation

- **Parent Directory**: [../README.md](../README.md) - Node.js/PM2 deployment (non-Docker)
- **Main Project**: [../../README.md](../../README.md) - Project overview
- **Troubleshooting**: [../TROUBLESHOOTING.md](../TROUBLESHOOTING.md) - Common issues and fixes

---

**Ready to deploy?** Start with [STEP-BY-STEP.md](STEP-BY-STEP.md)! 🚀
