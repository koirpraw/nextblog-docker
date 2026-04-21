# Docker-based ASG + ALB Deployment

This directory contains all scripts and documentation for deploying the Next.js blog application on AWS using Docker containers in an Auto Scaling Group behind an Application Load Balancer.

## ⚡ Two Deployment Approaches

### 🚀 Approach 1: Pre-built Images (RECOMMENDED) ⭐

**Pull pre-built Docker images from Docker Hub**

- ✅ **Fastest**: Golden AMI creation in 3-5 minutes
- ✅ **Most Reliable**: No build failures on instance
- ✅ **CI/CD Ready**: Build in pipeline, deploy anywhere
- ✅ **Easy Updates**: Just pull new tag, no AMI rebuild needed

**Start here**: **[QUICKSTART-PREBUILT.md](QUICKSTART-PREBUILT.md)** ⭐

**Documentation**:
- [QUICKSTART-PREBUILT.md](QUICKSTART-PREBUILT.md) - Quick start guide (15-25 min to production)
- [IMPROVED-WORKFLOW.md](IMPROVED-WORKFLOW.md) - Complete workflow guide
- [COMPARISON.md](COMPARISON.md) - Why this is better

**Key files**:
- `build-and-push.sh` - Build locally and push to Docker Hub
- `setup-golden-ami-docker-pull.sh` - Pull pre-built image (fast!)

### 🔨 Approach 2: Build on Instance (Traditional)

**Build Docker image on EC2 instance during Golden AMI creation**

- Takes 10-15 minutes
- Uses more memory (risky on t3.micro)
- Good if you can't use public Docker registry

**Key files**:
- `setup-golden-ami-docker.sh` - Build image on instance

## 📁 Directory Contents

### Documentation
- **[IMPROVED-WORKFLOW.md](IMPROVED-WORKFLOW.md)** - ⭐ NEW! Faster workflow using pre-built images
- **[STEP-BY-STEP.md](STEP-BY-STEP.md)** - Complete walkthrough (build on instance approach)
- **[DOCKER-DEPLOYMENT-GUIDE.md](DOCKER-DEPLOYMENT-GUIDE.md)** - Comprehensive reference guide
- **[DOCKER-QUICK-REFERENCE.md](DOCKER-QUICK-REFERENCE.md)** - Quick commands and troubleshooting

### Scripts

**Pre-built Image Approach (Recommended)**:
- **[build-and-push.sh](build-and-push.sh)** - Build locally and push to Docker Hub
- **[setup-golden-ami-docker-pull.sh](setup-golden-ami-docker-pull.sh)** - Pull pre-built image (fast!)

**Build on Instance Approach**:
- **[setup-golden-ami-docker.sh](setup-golden-ami-docker.sh)** - Build Docker image on instance

**Common**:
- **[user-data-docker.sh](user-data-docker.sh)** - User data script for Launch Template
- **[setup-aws-infrastructure.sh](setup-aws-infrastructure.sh)** - AWS infrastructure setup

## 🚀 Quick Start

### Recommended: Pre-built Image Workflow

```bash
# 1. Build and push to Docker Hub (on your local machine)
cd deployment/docker
nano build-and-push.sh  # Update DOCKER_USERNAME
./build-and-push.sh

# 2. Create Golden AMI (on EC2 instance)
nano setup-golden-ami-docker-pull.sh  # Update DOCKER_IMAGE
sudo ./setup-golden-ami-docker-pull.sh

# 3. Create AWS infrastructure (on your local machine)
nano setup-aws-infrastructure.sh  # Update AMI_ID
./setup-aws-infrastructure.sh
```

See [IMPROVED-WORKFLOW.md](IMPROVED-WORKFLOW.md) for complete guide.

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
