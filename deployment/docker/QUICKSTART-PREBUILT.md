# Quick Start - Pre-built Docker Image Workflow

The **fastest and simplest** way to deploy your Next.js blog to AWS ASG + ALB using Docker.

## 🎯 What You'll Do

1. Build Docker image locally (5 min)
2. Push to Docker Hub (2 min)
3. Create Golden AMI that pulls the image (5 min)
4. Deploy AWS infrastructure (5 min)
5. **Total: ~20 minutes** to production! 🚀

## ✅ Prerequisites

- [ ] AWS Account with credentials configured
- [ ] Docker Hub account (free: https://hub.docker.com/signup)
- [ ] Docker installed locally
- [ ] AWS CLI installed
- [ ] Security Group `WebServer-SG` created (ports 22, 80)
- [ ] EC2 Key Pair `sandbox-ec2-key.pem` created

## 🚀 Step 1: Build and Push Image (Local Machine)

```bash
# Navigate to project
cd /path/to/nextblog-docker

# Update Docker Hub username
nano deployment/docker/build-and-push.sh
# Change line 8: DOCKER_USERNAME="your-dockerhub-username"

# Build and push
cd deployment/docker
chmod +x build-and-push.sh
./build-and-push.sh
```

**What this does**:
- Builds optimized Docker image
- Logs you into Docker Hub
- Pushes image to Docker Hub

**Time**: 5-7 minutes

**Result**: Image available at `your-username/nextjs-blog:latest`

---

## 🏗️ Step 2: Create Golden AMI (EC2 Instance)

### Launch EC2 Instance

```bash
# Via AWS CLI
aws ec2 run-instances \
    --region us-east-1 \
    --image-id ami-0453ec754f44f9a4a \
    --instance-type t3.micro \
    --key-name sandbox-ec2-key \
    --security-groups WebServer-SG \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=golden-ami-builder}]'

# Get instance public IP from output or AWS Console
```

Or use AWS Console (faster for beginners):
- AMI: Amazon Linux 2023
- Instance type: t3.micro
- Key: sandbox-ec2-key
- Security group: WebServer-SG

### SSH and Run Setup

```bash
# SSH into instance
ssh -i ~/.ssh/sandbox-ec2-key.pem ec2-user@<instance-public-ip>

# Clone repo
git clone https://github.com/your-username/nextblog-docker.git
cd nextblog-docker

# Update Docker image name
nano deployment/docker/setup-golden-ami-docker-pull.sh
# Change line 11: DOCKER_IMAGE="your-username/nextjs-blog:latest"

# Run setup (only 3-5 minutes!)
chmod +x deployment/docker/setup-golden-ami-docker-pull.sh
sudo ./deployment/docker/setup-golden-ami-docker-pull.sh
```

**Time**: 3-5 minutes

### Test Deployment

```bash
# Still on EC2 instance
sudo /opt/scripts/deploy-app.sh

# Wait 30 seconds
sleep 30

# Test
curl http://localhost/api/health
# Should return: {"status":"healthy"}

# Success? Stop services and exit
sudo docker stop nextjs-blog
sudo systemctl stop nginx
exit
```

### Create AMI

```bash
# On your local machine

# Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
    --region us-east-1 \
    --filters "Name=tag:Name,Values=golden-ami-builder" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text)

# Create AMI
AMI_ID=$(aws ec2 create-image \
    --region us-east-1 \
    --instance-id $INSTANCE_ID \
    --name "nextjs-blog-golden-ami-$(date +%Y%m%d)" \
    --description "Next.js blog with Docker - Pull method" \
    --no-reboot \
    --query 'ImageId' \
    --output text)

echo "AMI ID: $AMI_ID"
echo "SAVE THIS ID!"

# Wait for AMI (2-5 minutes)
aws ec2 wait image-available --region us-east-1 --image-ids $AMI_ID
echo "✓ AMI ready!"

# Terminate builder instance
aws ec2 terminate-instances --region us-east-1 --instance-ids $INSTANCE_ID
```

**Time**: 2-5 minutes

---

## ☁️ Step 3: Deploy AWS Infrastructure (Local Machine)

```bash
cd deployment/docker

# Update AMI ID
nano setup-aws-infrastructure.sh
# Change line 11: AMI_ID="ami-XXXXXXXXX"  # Your AMI ID from Step 2

# Run setup
chmod +x setup-aws-infrastructure.sh
./setup-aws-infrastructure.sh
```

**What this creates**:
- Application Load Balancer
- Target Group (health check: `/api/health`)
- Launch Template (using your Golden AMI)
- Auto Scaling Group (2 instances)
- Scaling policy (CPU-based)

**Time**: 5-10 minutes

**Output**: ALB DNS name (your application URL!)

---

## ✅ Step 4: Verify Deployment

### Watch Instances Launch

```bash
# Monitor ASG (updates every 5 seconds)
watch -n 5 'aws autoscaling describe-auto-scaling-groups \
    --region us-east-1 \
    --auto-scaling-group-names nextjs-blog-asg \
    --query "AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState]" \
    --output table'

# Wait for both instances to reach "InService"
# Takes 2-4 minutes
```

### Check Target Health

```bash
# Get Target Group ARN
TG_ARN=$(aws elbv2 describe-target-groups \
    --region us-east-1 \
    --names nextjs-blog-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

# Check health
aws elbv2 describe-target-health \
    --region us-east-1 \
    --target-group-arn $TG_ARN

# Look for "State": "healthy" for both targets
```

### Access Your Application

```bash
# Get ALB DNS
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --region us-east-1 \
    --names nextjs-blog-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

echo "Your application is live at:"
echo "http://$ALB_DNS"

# Test
curl http://$ALB_DNS/api/health

# Open in browser
open http://$ALB_DNS  # Mac
# or visit the URL in your browser
```

**🎉 If you see your blog, you're done!**

---

## 🔄 Updating Your Application

When you make code changes:

```bash
# 1. Build and push new image
cd deployment/docker
./build-and-push.sh

# 2. Option A: Auto-update (edit user-data-docker.sh to pull latest)
# 2. Option B: Manual update on running instances
ssh -i key.pem ec2-user@<instance-ip>
sudo docker pull your-username/nextjs-blog:latest
sudo docker tag your-username/nextjs-blog:latest nextjs-blog:latest
sudo /opt/scripts/deploy-app.sh

# 2. Option C: Create new Golden AMI (for major updates)
# Repeat Step 2
```

---

## 📊 Complete Timeline

| Step | Duration | What Happens |
|------|----------|--------------|
| Build & Push | 5-7 min | Docker image built and uploaded to Hub |
| Golden AMI Setup | 3-5 min | EC2 instance pulls image, installs NGINX |
| AMI Creation | 2-5 min | AWS creates AMI snapshot |
| Infrastructure | 3-5 min | ALB, ASG, Launch Template created |
| Instance Launch | 2-4 min | ASG launches 2 instances |
| **Total** | **15-25 min** | From zero to production! |

---

## 💡 Pro Tips

### Faster Development Cycle

```bash
# Test locally before pushing
docker build -t nextjs-blog:test .
docker run -d -p 3000:3000 nextjs-blog:test
curl http://localhost:3000/api/health
docker stop $(docker ps -q --filter ancestor=nextjs-blog:test)
```

### Version Your Images

```bash
# Tag with version
docker tag your-username/nextjs-blog:latest your-username/nextjs-blog:v1.0.0
docker push your-username/nextjs-blog:v1.0.0

# Use specific version in Golden AMI
DOCKER_IMAGE="your-username/nextjs-blog:v1.0.0"
```

### Enable Auto-Updates

Edit `deployment/docker/user-data-docker.sh`, uncomment lines 27-34:
```bash
# Pulls latest image on every instance launch
echo "Pulling latest application code..."
sudo docker pull your-username/nextjs-blog:latest
```

---

## 🆘 Troubleshooting

### Image Pull Failed?

```bash
# Make sure image is public on Docker Hub
# Or login on EC2 instance:
echo "YOUR_PASSWORD" | sudo docker login -u YOUR_USERNAME --password-stdin
```

### Targets Unhealthy?

```bash
# SSH into instance
ssh -i key.pem ec2-user@<instance-ip>

# Check logs
sudo tail -f /var/log/user-data.log
sudo docker logs nextjs-blog --follow

# Restart if needed
sudo /opt/scripts/deploy-app.sh
```

### Can't Access ALB?

- Wait 5 minutes for initial health checks
- Verify Security Group allows port 80 from 0.0.0.0/0
- Check both targets are "healthy"

---

## 🗑️ Clean Up

To delete everything and stop charges:

```bash
# Delete ASG (with instances)
aws autoscaling delete-auto-scaling-group \
    --region us-east-1 \
    --auto-scaling-group-name nextjs-blog-asg \
    --force-delete

# Wait, then delete other resources
sleep 60
aws ec2 delete-launch-template --region us-east-1 --launch-template-name nextjs-blog-lt

ALB_ARN=$(aws elbv2 describe-load-balancers --region us-east-1 --names nextjs-blog-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text)
aws elbv2 delete-load-balancer --region us-east-1 --load-balancer-arn $ALB_ARN

sleep 60
TG_ARN=$(aws elbv2 describe-target-groups --region us-east-1 --names nextjs-blog-tg --query 'TargetGroups[0].TargetGroupArn' --output text)
aws elbv2 delete-target-group --region us-east-1 --target-group-arn $TG_ARN
```

---

## 📚 Next Steps

- Add HTTPS: Use ACM certificate with ALB
- Custom domain: Point Route 53 to ALB
- CI/CD: Automate with GitHub Actions
- Monitoring: Set up CloudWatch alarms
- Backups: Configure automated snapshots

---

**Questions?** Check:
- [IMPROVED-WORKFLOW.md](IMPROVED-WORKFLOW.md) - Detailed guide
- [COMPARISON.md](COMPARISON.md) - Why this approach is better
- [DOCKER-QUICK-REFERENCE.md](DOCKER-QUICK-REFERENCE.md) - Command reference

**Happy deploying! 🚀**
