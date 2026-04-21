# Step-by-Step Deployment Guide

This is your action plan to deploy the Next.js blog to AWS ASG + ALB with Docker.

---

## ✅ Pre-Deployment Checklist

Before you start, ensure you have:

- [x] AWS Account with access to us-east-1 (N. Virginia)
- [x] AWS CLI installed and configured (`aws configure`)
- [x] EC2 Key Pair: `sandbox-ec2-key.pem` (already created)
- [x] Security Group: `WebServer-SG` with SSH (22) and HTTP (80) enabled
- [ ] GitHub repository pushed with all latest code
- [ ] Update repository URL in `deployment/setup-golden-ami-docker.sh` (line 75)

---

## 📍 Phase 1: Create Golden AMI (One-Time Setup)

**Time estimate: 15-20 minutes**

### Step 1: Launch EC2 Instance for Golden AMI

Choose one method:

**Option A: AWS Console**
1. Go to EC2 → Launch Instance
2. Settings:
   - Name: `nextjs-golden-ami-builder`
   - AMI: **Amazon Linux 2023 AMI** (HVM, SSD)
   - Instance type: `t3.micro` or `t2.micro`
   - Key pair: `sandbox-ec2-key`
   - Security group: `WebServer-SG`
   - Storage: 20 GB gp3
3. Click "Launch Instance"

**Option B: AWS CLI**
```bash
aws ec2 run-instances \
    --region us-east-1 \
    --image-id ami-0453ec754f44f9a4a \
    --instance-type t3.micro \
    --key-name sandbox-ec2-key \
    --security-groups WebServer-SG \
    --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=20,VolumeType=gp3}' \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=nextjs-golden-ami-builder}]'
```

### Step 2: SSH into Instance

```bash
# Get instance public IP from AWS Console
INSTANCE_IP="<your-instance-public-ip>"

# Connect via SSH
ssh -i ~/.ssh/sandbox-ec2-key.pem ec2-user@$INSTANCE_IP
```

### Step 3: Update Repository URL (IMPORTANT!)

Before running the setup script, update the repository URL:

```bash
# On your LOCAL machine, edit the file:
nano deployment/docker/setup-golden-ami-docker.sh

# Find line 75 and change:
REPO_URL="https://github.com/koirpraw/nextblog-docker.git"

# Save and commit
git add deployment/docker/setup-golden-ami-docker.sh
git commit -m "Update repository URL for Golden AMI"
git push
```

### Step 4: Run Golden AMI Setup Script

```bash
# On the EC2 instance, clone your repo
cd /home/ec2-user
git clone https://github.com/koirpraw/nextblog-docker.git
cd nextblog-docker

# Make script executable
chmod +x deployment/docker/setup-golden-ami-docker.sh

# Run the setup script
sudo ./deployment/docker/setup-golden-ami-docker.sh
```

**What happens:** The script will install Docker, NGINX, clone your app, and build the Docker image. This takes 5-10 minutes.

### Step 5: Test Before Creating AMI

```bash
# Still on the EC2 instance

# Run the deployment script
sudo /opt/scripts/deploy-app.sh

# Wait 30 seconds
sleep 30

# Test health endpoint
curl http://localhost/api/health
# Expected: {"status":"healthy"}

# Test homepage
curl http://localhost
# Expected: HTML content

# Check Docker container
sudo docker ps
# Expected: See 'nextjs-blog' container running

# If all tests pass, proceed to next step!
```

### Step 6: Stop Services and Prepare for AMI

```bash
# Still on the EC2 instance

# Stop services
sudo docker stop nextjs-blog
sudo systemctl stop nginx

# Clean up logs
sudo rm -f /var/log/user-data.log
sudo truncate -s 0 /var/log/nginx/access.log
sudo truncate -s 0 /var/log/nginx/error.log

# Exit
exit
```

### Step 7: Create AMI

**Option A: AWS Console**
1. Go to EC2 → Instances
2. Select `nextjs-golden-ami-builder`
3. Actions → Image and templates → Create image
4. Image name: `nextjs-blog-golden-ami-v1`
5. Description: `Next.js blog with Docker pre-built - AL2023`
6. Click "Create image"

**Option B: AWS CLI**
```bash
# Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
    --region us-east-1 \
    --filters "Name=tag:Name,Values=nextjs-golden-ami-builder" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text)

# Create AMI
AMI_ID=$(aws ec2 create-image \
    --region us-east-1 \
    --instance-id $INSTANCE_ID \
    --name "nextjs-blog-golden-ami-v1" \
    --description "Next.js blog with Docker pre-built - AL2023" \
    --no-reboot \
    --query 'ImageId' \
    --output text)

echo "AMI ID: $AMI_ID"
echo "SAVE THIS AMI ID!"
```

### Step 8: Wait for AMI Creation

```bash
# Check AMI status (every 30 seconds)
aws ec2 describe-images \
    --region us-east-1 \
    --image-ids $AMI_ID \
    --query 'Images[0].State'

# Or wait automatically (2-5 minutes)
aws ec2 wait image-available \
    --region us-east-1 \
    --image-ids $AMI_ID

echo "✓ AMI is ready!"
```

### Step 9: Terminate Builder Instance

```bash
# Terminate the builder instance
aws ec2 terminate-instances \
    --region us-east-1 \
    --instance-ids $INSTANCE_ID
```

**✅ Phase 1 Complete!** You now have a Golden AMI with Docker and your app pre-built.

---

## 📍 Phase 2: Set Up AWS Infrastructure

**Time estimate: 5-10 minutes**

### Step 10: Update Infrastructure Script

```bash
# On your LOCAL machine

# Edit the infrastructure script
nano deployment/docker/setup-aws-infrastructure.sh

# Update line 11 with your AMI ID from Step 7:
AMI_ID="ami-XXXXXXXXX"  # Your Golden AMI ID

# Save the file
```

### Step 11: Run Infrastructure Setup

```bash
# On your LOCAL machine
cd deployment/docker

# Make script executable
chmod +x setup-aws-infrastructure.sh

# Run the script
./setup-aws-infrastructure.sh
```

**What happens:**
1. Creates Target Group with `/api/health` health checks
2. Creates Application Load Balancer
3. Creates Listener (HTTP:80)
4. Creates Launch Template
5. Creates Auto Scaling Group (2 instances)
6. Configures CPU-based scaling

**Time:** 2-3 minutes

**IMPORTANT:** The script will output the ALB DNS name. **Save this!** This is your application URL.

---

## 📍 Phase 3: Verify Deployment

**Time estimate: 3-5 minutes**

### Step 12: Monitor Instance Launch

```bash
# Watch ASG status (refreshes every 5 seconds)
watch -n 5 'aws autoscaling describe-auto-scaling-groups \
    --region us-east-1 \
    --auto-scaling-group-names nextjs-blog-asg \
    --query "AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState,HealthStatus]" \
    --output table'

# Wait for instances to reach "InService" state
# Expected time: 3-4 minutes
```

### Step 13: Check Target Health

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

### Step 14: Access Your Application

```bash
# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --region us-east-1 \
    --names nextjs-blog-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

echo "Application URL: http://$ALB_DNS"

# Test health endpoint
curl http://$ALB_DNS/api/health
# Expected: {"status":"healthy"}

# Open in browser
open http://$ALB_DNS
```

**✅ If you see your blog, deployment is successful! 🎉**

---

## 🎯 Common Next Steps

### Test Auto Scaling

```bash
# Scale to 3 instances
aws autoscaling set-desired-capacity \
    --region us-east-1 \
    --auto-scaling-group-name nextjs-blog-asg \
    --desired-capacity 3

# Wait and verify
aws autoscaling describe-auto-scaling-groups \
    --region us-east-1 \
    --auto-scaling-group-names nextjs-blog-asg \
    --query "AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState]" \
    --output table

# Scale back to 2
aws autoscaling set-desired-capacity \
    --region us-east-1 \
    --auto-scaling-group-name nextjs-blog-asg \
    --desired-capacity 2
```

### Debug an Instance

```bash
# Get instance IP
aws ec2 describe-instances \
    --region us-east-1 \
    --filters "Name=tag:Name,Values=nextjs-blog-asg" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text

# SSH into instance
ssh -i ~/.ssh/sandbox-ec2-key.pem ec2-user@<instance-ip>

# Check logs
sudo tail -f /var/log/user-data.log
sudo docker logs nextjs-blog --follow
```

---

## 🗑️ Clean Up (When Done)

To avoid charges, delete all resources:

```bash
# Delete Auto Scaling Group (with all instances)
aws autoscaling delete-auto-scaling-group \
    --region us-east-1 \
    --auto-scaling-group-name nextjs-blog-asg \
    --force-delete

# Wait for instances to terminate
sleep 60

# Delete Launch Template
aws ec2 delete-launch-template \
    --region us-east-1 \
    --launch-template-name nextjs-blog-lt

# Delete ALB
ALB_ARN=$(aws elbv2 describe-load-balancers \
    --region us-east-1 \
    --names nextjs-blog-alb \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)

aws elbv2 delete-load-balancer \
    --region us-east-1 \
    --load-balancer-arn $ALB_ARN

# Wait for ALB deletion
sleep 60

# Delete Target Group
TG_ARN=$(aws elbv2 describe-target-groups \
    --region us-east-1 \
    --names nextjs-blog-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

aws elbv2 delete-target-group \
    --region us-east-1 \
    --target-group-arn $TG_ARN

echo "✓ All resources deleted"
```

---

## 📚 Documentation Reference

- **Full Guide**: [DOCKER-DEPLOYMENT-GUIDE.md](DOCKER-DEPLOYMENT-GUIDE.md)
- **Quick Reference**: [DOCKER-QUICK-REFERENCE.md](DOCKER-QUICK-REFERENCE.md)
- **Troubleshooting**: [../TROUBLESHOOTING.md](../TROUBLESHOOTING.md)

---

## 🆘 Troubleshooting Quick Tips

**Targets not becoming healthy?**
- Wait 5 minutes (health check grace period)
- SSH into instance and check: `sudo docker logs nextjs-blog`
- Test locally on instance: `curl http://localhost/api/health`

**Container won't start?**
- Check if image exists: `sudo docker images | grep nextjs-blog`
- Rebuild if needed: `cd /opt/nextjs-app/app && sudo docker build -t nextjs-blog:latest .`

**Can't access ALB?**
- Verify security group allows port 80 from 0.0.0.0/0
- Check target health: All must be "healthy"
- Wait 2-3 minutes after instance launch

---

**Happy Deploying! 🚀**

Need help? Check the troubleshooting guide or review instance logs.
