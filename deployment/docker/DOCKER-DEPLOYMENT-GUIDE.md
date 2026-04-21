# Docker-based ASG + ALB Deployment Guide

Complete guide for deploying the Next.js blog application on AWS using Docker, Auto Scaling Groups, and Application Load Balancer with optimized launch times via Golden AMI.

## 📋 Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Phase 1: Create Golden AMI](#phase-1-create-golden-ami)
4. [Phase 2: Set Up AWS Infrastructure](#phase-2-set-up-aws-infrastructure)
5. [Phase 3: Verify Deployment](#phase-3-verify-deployment)
6. [Monitoring & Troubleshooting](#monitoring--troubleshooting)
7. [Cost Optimization](#cost-optimization)
8. [Cleanup](#cleanup)

---

## 🏗️ Architecture Overview

```
Internet
    ↓
Application Load Balancer (ALB)
    ↓
Target Group (Health Check: /api/health)
    ↓
Auto Scaling Group (Min: 1, Max: 3, Desired: 2)
    ↓
EC2 Instances (Golden AMI + Docker)
    ↓
NGINX (Port 80) → Docker Container (Port 3000)
    ↓
Next.js Application
```

**Key Features:**
- **Fast Launch Time**: ~2-3 minutes (Docker image pre-built in Golden AMI)
- **High Availability**: Multi-AZ deployment with ALB health checks
- **Auto Scaling**: CPU-based scaling (target: 50%)
- **Zero Downtime**: Rolling updates with connection draining

---

## ✅ Prerequisites

### AWS Resources (Already Created)
- ✅ EC2 Key Pair: `sandbox-ec2-key.pem` (RSA format)
- ✅ Security Group: `WebServer-SG` with:
  - Port 22 (SSH) from your IP
  - Port 80 (HTTP) from 0.0.0.0/0

### Tools Required
- AWS CLI installed and configured
- SSH client
- Git
- Your GitHub repository URL

### Sandbox Constraints
- Region: `us-east-1` (N. Virginia)
- Instance Types: `t3.micro` or `t2.micro`
- Max Instances: 5
- Volume: 30 GB max (gp2/gp3)

---

## 🎯 Phase 1: Create Golden AMI

The Golden AMI approach pre-installs Docker and pre-builds the Docker image, reducing instance launch time from ~10 minutes to ~2-3 minutes.

### Step 1.1: Update Repository URL

First, update the repository URL in the setup script:

```bash
# Edit deployment/setup-golden-ami-docker.sh
# Change line ~75:
REPO_URL="https://github.com/YOUR_USERNAME/nextblog-docker.git"
```

### Step 1.2: Launch Base EC2 Instance

Launch a fresh EC2 instance to create the Golden AMI:

```bash
# Via AWS CLI
aws ec2 run-instances \
    --region us-east-1 \
    --image-id ami-0453ec754f44f9a4a \
    --instance-type t3.micro \
    --key-name sandbox-ec2-key \
    --security-groups WebServer-SG \
    --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=20,VolumeType=gp3}' \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=nextjs-golden-ami-builder}]'
```

**Or via AWS Console:**
1. Go to EC2 → Launch Instance
2. Name: `nextjs-golden-ami-builder`
3. AMI: **Amazon Linux 2023 AMI** (HVM, SSD Volume Type)
4. Instance type: `t3.micro`
5. Key pair: `sandbox-ec2-key`
6. Security group: `WebServer-SG`
7. Storage: 20 GB gp3
8. Launch instance

### Step 1.3: SSH into Instance

```bash
# Get instance public IP from AWS Console or CLI
INSTANCE_IP="<your-instance-public-ip>"

# SSH into instance
ssh -i ~/.ssh/sandbox-ec2-key.pem ec2-user@$INSTANCE_IP
```

### Step 1.4: Run Golden AMI Setup Script

Copy the setup script to the instance and run it:

**Option A: Clone repository**
```bash
# On the EC2 instance
git clone https://github.com/YOUR_USERNAME/nextblog-docker.git
cd nextblog-docker
chmod +x deployment/docker/setup-golden-ami-docker.sh
sudo ./deployment/docker/setup-golden-ami-docker.sh
```

**Option B: Direct download**
```bash
# On the EC2 instance
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/nextblog-docker/main/deployment/docker/setup-golden-ami-docker.sh
chmod +x setup-golden-ami-docker.sh
sudo ./setup-golden-ami-docker.sh
```

**What this script does:**
- ✅ Installs Docker and Docker Compose
- ✅ Installs NGINX
- ✅ Clones your application code
- ✅ **Builds Docker image** (this is the time-consuming part we do once)
- ✅ Creates NGINX reverse proxy configuration
- ✅ Creates deployment script at `/opt/scripts/deploy-app.sh`
- ✅ Sets up content directory for markdown posts

**Expected duration:** 5-10 minutes (mostly Docker image build)

### Step 1.5: Test the Deployment

Before creating the AMI, test that everything works:

```bash
# Run deployment script
sudo /opt/scripts/deploy-app.sh

# Wait 30 seconds for services to start
sleep 30

# Test health endpoint
curl http://localhost/api/health
# Should return: {"status":"healthy"}

# Test homepage
curl http://localhost
# Should return HTML content

# Check Docker container
sudo docker ps
# Should show 'nextjs-blog' container running

# Check NGINX
sudo systemctl status nginx
```

If all tests pass, you're ready to create the AMI!

### Step 1.6: Prepare Instance for AMI Creation

Clean up before creating the AMI:

```bash
# Stop services (they'll start automatically on new instances via user-data)
sudo docker stop nextjs-blog
sudo systemctl stop nginx

# Clear logs
sudo rm -f /var/log/user-data.log
sudo truncate -s 0 /var/log/nginx/access.log
sudo truncate -s 0 /var/log/nginx/error.log

# Clear command history (optional, for security)
history -c && cat /dev/null > ~/.bash_history

# Exit the instance
exit
```

### Step 1.7: Create Golden AMI

**Via AWS Console:**
1. Go to EC2 → Instances
2. Select `nextjs-golden-ami-builder`
3. Actions → Image and templates → Create image
4. Image name: `nextjs-blog-golden-ami-v1`
5. Image description: `Next.js blog with Docker pre-built - Amazon Linux 2023`
6. No reboot: ☑️ (optional, recommended)
7. Create image

**Via AWS CLI:**
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
    --description "Next.js blog with Docker pre-built - Amazon Linux 2023" \
    --no-reboot \
    --query 'ImageId' \
    --output text)

echo "AMI ID: $AMI_ID"
```

**Wait for AMI to become available** (2-5 minutes):

```bash
# Check AMI status
aws ec2 describe-images \
    --region us-east-1 \
    --image-ids $AMI_ID \
    --query 'Images[0].State'

# Or wait automatically
aws ec2 wait image-available \
    --region us-east-1 \
    --image-ids $AMI_ID

echo "✓ AMI is ready!"
```

### Step 1.8: Terminate Builder Instance

Once the AMI is created, you can terminate the builder instance:

```bash
aws ec2 terminate-instances \
    --region us-east-1 \
    --instance-ids $INSTANCE_ID
```

**Save your AMI ID!** You'll need it for the next phase.

---

## 🚀 Phase 2: Set Up AWS Infrastructure

Now we'll create the ALB, Target Group, Launch Template, and Auto Scaling Group.

### Option A: Automated Setup (Recommended)

Use the provided script to set up everything automatically:

```bash
# On your local machine
cd deployment/docker

# Edit setup-aws-infrastructure.sh
# Update AMI_ID with your Golden AMI ID from Phase 1
nano setup-aws-infrastructure.sh
# Change: AMI_ID="ami-XXXXXXXXX"

# Make script executable
chmod +x setup-aws-infrastructure.sh

# Run the script
./setup-aws-infrastructure.sh
```

The script will:
1. ✅ Auto-detect VPC and Subnets
2. ✅ Create Target Group with `/api/health` health checks
3. ✅ Create Application Load Balancer
4. ✅ Create Listener (HTTP:80)
5. ✅ Create Launch Template with user-data
6. ✅ Create Auto Scaling Group (min:1, max:3, desired:2)
7. ✅ Configure CPU-based scaling policy

**Save the ALB DNS name** from the script output - this is your application URL!

### Option B: Manual Setup via AWS Console

<details>
<summary>Click to expand manual setup instructions</summary>

#### 2.1: Create Target Group

1. Go to EC2 → Target Groups → Create target group
2. Configuration:
   - Target type: **Instances**
   - Target group name: `nextjs-blog-tg`
   - Protocol: HTTP, Port: 80
   - VPC: Select default VPC
   - Protocol version: HTTP1
3. Health checks:
   - Protocol: HTTP
   - Path: `/api/health`
   - Interval: 30 seconds
   - Timeout: 5 seconds
   - Healthy threshold: 2
   - Unhealthy threshold: 3
   - Success codes: 200
4. Advanced settings:
   - Deregistration delay: 30 seconds
   - Stickiness: Enabled (1 day)
5. Create target group

#### 2.2: Create Application Load Balancer

1. Go to EC2 → Load Balancers → Create load balancer
2. Select **Application Load Balancer**
3. Basic configuration:
   - Name: `nextjs-blog-alb`
   - Scheme: Internet-facing
   - IP address type: IPv4
4. Network mapping:
   - VPC: Default VPC
   - Availability Zones: Select **at least 2 AZs** (required for ALB)
5. Security groups:
   - Select `WebServer-SG`
6. Listeners:
   - Protocol: HTTP, Port: 80
   - Default action: Forward to `nextjs-blog-tg`
7. Create load balancer

**Save the ALB DNS name** (e.g., `nextjs-blog-alb-1234567890.us-east-1.elb.amazonaws.com`)

#### 2.3: Create Launch Template

1. Go to EC2 → Launch Templates → Create launch template
2. Template name: `nextjs-blog-lt`
3. Template version description: `Docker-based Next.js blog v1`
4. Application and OS Images:
   - My AMIs → Owned by me
   - Select your Golden AMI: `nextjs-blog-golden-ami-v1`
5. Instance type: `t3.micro` (or `t2.micro`)
6. Key pair: `sandbox-ec2-key`
7. Network settings:
   - Don't include in launch template (ASG will handle this)
8. Security groups:
   - Select `WebServer-SG`
9. Storage: 20 GB gp3 (default from AMI)
10. Advanced details:
    - User data: Copy content from `deployment/docker/user-data-docker.sh`
    - Monitoring: Enable detailed monitoring (optional)
11. Create launch template

#### 2.4: Create Auto Scaling Group

1. Go to EC2 → Auto Scaling Groups → Create Auto Scaling Group
2. Step 1: Choose launch template
   - Name: `nextjs-blog-asg`
   - Launch template: `nextjs-blog-lt` (Latest version)
3. Step 2: Network
   - VPC: Default VPC
   - Availability Zones: Select **same AZs as ALB**
4. Step 3: Load balancing
   - Attach to an existing load balancer
   - Choose from your load balancer target groups
   - Select: `nextjs-blog-tg`
   - Health checks:
     - ✅ Turn on ELB health checks
     - Health check grace period: 300 seconds
5. Step 4: Group size and scaling
   - Desired capacity: 2
   - Minimum capacity: 1
   - Maximum capacity: 3
   - Scaling policies:
     - ✅ Target tracking scaling policy
     - Metric: Average CPU utilization
     - Target value: 50
6. Step 5: Add notifications (skip)
7. Step 6: Add tags
   - Key: `Name`, Value: `nextjs-blog-asg`
   - Key: `Environment`, Value: `production`
8. Review and create

</details>

---

## ✅ Phase 3: Verify Deployment

### Step 3.1: Monitor Instance Launch

The ASG will launch 2 instances. Monitor their progress:

```bash
# Watch ASG activity
watch -n 5 'aws autoscaling describe-auto-scaling-groups \
    --region us-east-1 \
    --auto-scaling-group-names nextjs-blog-asg \
    --query "AutoScalingGroups[0].[DesiredCapacity,Instances[*].[InstanceId,LifecycleState,HealthStatus]]"'
```

**Expected states:**
1. `Pending` (instance launching) - 1 minute
2. `Pending:Wait` (user-data running) - 2-3 minutes
3. `InService` (healthy and serving traffic)

### Step 3.2: Check Target Health

```bash
# Get Target Group ARN
TG_ARN=$(aws elbv2 describe-target-groups \
    --region us-east-1 \
    --names nextjs-blog-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

# Check target health
aws elbv2 describe-target-health \
    --region us-east-1 \
    --target-group-arn $TG_ARN
```

**Healthy targets show:**
```json
{
    "TargetHealth": {
        "State": "healthy"
    }
}
```

**If unhealthy, check:**
- Instance logs: SSH into instance and check `/var/log/user-data.log`
- Docker logs: `sudo docker logs nextjs-blog`
- NGINX logs: `sudo tail -f /var/log/nginx/nextjs-error.log`

### Step 3.3: Access Your Application

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

# Test homepage
curl http://$ALB_DNS
```

**Open in browser:**
```
http://<your-alb-dns-name>
```

### Step 3.4: Test Auto Scaling

Verify that auto scaling works:

```bash
# Manually change desired capacity
aws autoscaling set-desired-capacity \
    --region us-east-1 \
    --auto-scaling-group-name nextjs-blog-asg \
    --desired-capacity 3

# Watch new instance launch
watch -n 5 'aws autoscaling describe-auto-scaling-groups \
    --region us-east-1 \
    --auto-scaling-group-names nextjs-blog-asg \
    --query "AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState]"'

# Scale back down
aws autoscaling set-desired-capacity \
    --region us-east-1 \
    --auto-scaling-group-name nextjs-blog-asg \
    --desired-capacity 2
```

---

## 🔍 Monitoring & Troubleshooting

### View Instance Logs

```bash
# Get running instance IPs
aws ec2 describe-instances \
    --region us-east-1 \
    --filters "Name=tag:Name,Values=nextjs-blog-asg" "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress]' \
    --output table

# SSH into an instance
ssh -i ~/.ssh/sandbox-ec2-key.pem ec2-user@<instance-ip>

# Check logs
sudo tail -f /var/log/user-data.log
sudo docker logs nextjs-blog --follow
sudo tail -f /var/log/nginx/nextjs-error.log
```

### Common Issues

#### Targets not becoming healthy
- Check security group allows port 80
- Verify `/api/health` endpoint responds with 200
- Check Docker container is running: `sudo docker ps`
- Check NGINX is running: `sudo systemctl status nginx`

#### Slow instance launch
- Expected: 2-3 minutes with Golden AMI
- If slower: Check user-data logs for errors
- If much slower: Verify Docker image is in Golden AMI: `sudo docker images`

#### Application not responding
- Check Docker logs: `sudo docker logs nextjs-blog`
- Restart container: `sudo docker restart nextjs-blog`
- Restart NGINX: `sudo systemctl restart nginx`

### Helpful Diagnostic Script

Use the provided diagnostic script:

```bash
# SSH into instance
ssh -i ~/.ssh/sandbox-ec2-key.pem ec2-user@<instance-ip>

# Download and run diagnostic
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/nextblog-docker/main/deployment/docker/diagnose-asg-instance.sh
chmod +x diagnose-asg-instance.sh
./diagnose-asg-instance.sh
```

---

## 💰 Cost Optimization

### Current Setup Costs (us-east-1)
- **2x t3.micro instances**: ~$12/month (on-demand)
- **ALB**: ~$16/month + data transfer
- **Total**: ~$30/month

### Optimization Options

#### 1. Use Spot Instances (up to 70% savings)
```bash
# Update Launch Template to use Spot
aws ec2 modify-launch-template \
    --region us-east-1 \
    --launch-template-name nextjs-blog-lt \
    --default-version '$Latest' \
    --launch-template-data '{
        "InstanceMarketOptions": {
            "MarketType": "spot",
            "SpotOptions": {
                "MaxPrice": "0.0042",
                "SpotInstanceType": "one-time"
            }
        }
    }'
```

#### 2. Reduce to 1 Instance for Non-Production
```bash
aws autoscaling update-auto-scaling-group \
    --region us-east-1 \
    --auto-scaling-group-name nextjs-blog-asg \
    --min-size 1 \
    --desired-capacity 1
```

#### 3. Schedule Auto Scaling (e.g., turn off at night)
- Use AWS EventBridge + Lambda to modify desired capacity
- Save ~50% if running 12h/day

---

## 🗑️ Cleanup

To delete all resources and stop charges:

```bash
# Delete Auto Scaling Group (with instances)
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

# Wait for ALB to delete
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

# Deregister and delete AMI (optional)
AMI_ID=$(aws ec2 describe-images \
    --region us-east-1 \
    --owners self \
    --filters "Name=name,Values=nextjs-blog-golden-ami-v1" \
    --query 'Images[0].ImageId' \
    --output text)

aws ec2 deregister-image \
    --region us-east-1 \
    --image-id $AMI_ID

echo "✓ All resources deleted"
```

---

## 📚 Next Steps

1. **Custom Domain**: Point a domain to the ALB using Route 53
2. **HTTPS**: Add an SSL certificate to the ALB using ACM
3. **CI/CD**: Set up GitHub Actions to build new AMIs on code changes
4. **Monitoring**: Set up CloudWatch alarms for CPU, memory, and errors
5. **Backups**: Configure automated EBS snapshots
6. **WAF**: Add AWS WAF to protect against common web attacks

---

## 📞 Support

If you encounter issues:
1. Check [../TROUBLESHOOTING.md](../TROUBLESHOOTING.md)
2. Review instance logs (`/var/log/user-data.log`)
3. Check Docker logs (`sudo docker logs nextjs-blog`)
4. Verify security group settings
5. Ensure AMI is from correct region

---

**Happy Deploying! 🚀**
