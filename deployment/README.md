# AWS Auto Scaling Group Deployment Guide

This guide explains how to deploy the Next.js application in an AWS Auto Scaling Group (ASG) behind an Application Load Balancer (ALB).

## Architecture Overview

```
Internet → ALB → Target Group → ASG → EC2 Instances (NGINX → Next.js)
```

## Prerequisites

- AWS Account with EC2, ALB, and ASG permissions
- GitHub repository with your Next.js application
- Basic knowledge of AWS services

## Deployment Approaches

### Approach 1: Golden AMI (Recommended)

**Pros:**
- Faster instance launch time (~2-3 minutes)
- Pre-installed dependencies
- Consistent environment
- Better for rapid scaling

**Cons:**
- Requires AMI maintenance
- Need to rebuild AMI for infrastructure changes

### Approach 2: Full Bootstrap in User Data

**Pros:**
- No AMI to maintain
- Always uses latest base image
- Easy to update dependencies

**Cons:**
- Slower instance launch time (~5-10 minutes)
- More network bandwidth usage
- Higher chance of transient failures

## Quick Start (Golden AMI Approach)

### Step 1: Prepare Your Repository

1. Ensure your repository has the health check endpoint:
   - File: `src/app/api/health/route.ts`
   - This endpoint is required for ALB health checks

2. Update the repository URL in deployment scripts:
   ```bash
   # In deployment/setup-golden-ami.sh
   REPO_URL="https://github.com/YOUR_USERNAME/markdown-editor-blog.git"
   ```

### Step 2: Create Golden AMI

1. Launch a fresh EC2 instance (Amazon Linux 2)

2. SSH into the instance:
   ```bash
   ssh -i your-key.pem ec2-user@instance-ip
   ```

3. Download and run the Golden AMI setup script:
   ```bash
   curl -O https://raw.githubusercontent.com/YOUR_USERNAME/markdown-editor-blog/main/deployment/setup-golden-ami.sh
   chmod +x setup-golden-ami.sh
   ./setup-golden-ami.sh
   ```

4. Update the repository URL in the deployment script:
   ```bash
   sudo nano /usr/local/bin/deploy-nextjs.sh
   # Change REPO_URL to your repository
   ```

5. Test the deployment:
   ```bash
   /usr/local/bin/deploy-nextjs.sh
   ```

6. Verify the application is running:
   ```bash
   pm2 status
   curl http://localhost:3000
   curl http://localhost/api/health
   ```

7. Clean up before creating AMI:
   ```bash
   pm2 delete all
   sudo rm -rf /opt/nextjs-app/.git
   sudo rm -rf /opt/nextjs-app/node_modules
   sudo rm -rf /opt/nextjs-app/.next
   history -c
   ```

8. Create AMI from AWS Console:
   - EC2 → Instances → Select instance → Actions → Image and templates → Create image
   - Name: `nextjs-blog-golden-ami-v1`
   - Description: Add version info and date
   - Create Image

### Step 3: Create IAM Role (Optional but Recommended)

Create an IAM role with these policies:
- `CloudWatchAgentServerPolicy` (for logs)
- `AmazonSSMManagedInstanceCore` (for Systems Manager)

### Step 4: Create Security Groups

**ALB Security Group** (`nextjs-alb-sg`):
```
Inbound Rules:
- HTTP (80) from 0.0.0.0/0
- HTTPS (443) from 0.0.0.0/0

Outbound Rules:
- HTTP (80) to Instance Security Group
```

**Instance Security Group** (`nextjs-instance-sg`):
```
Inbound Rules:
- HTTP (80) from ALB Security Group
- SSH (22) from Your IP (for debugging)

Outbound Rules:
- All traffic to 0.0.0.0/0
```

### Step 5: Create Target Group

1. Go to: EC2 → Target Groups → Create target group

2. Configuration:
   - Target type: Instances
   - Name: `nextjs-blog-tg`
   - Protocol: HTTP, Port: 80
   - VPC: Your VPC
   - Health check path: `/api/health`
   - Health check interval: 30 seconds
   - Healthy threshold: 2
   - Unhealthy threshold: 3
   - Timeout: 5 seconds
   - Success codes: 200

### Step 6: Create Application Load Balancer

1. Go to: EC2 → Load Balancers → Create Load Balancer

2. Configuration:
   - Type: Application Load Balancer
   - Name: `nextjs-blog-alb`
   - Scheme: Internet-facing
   - IP address type: IPv4
   - VPC: Your VPC
   - Subnets: Select at least 2 availability zones
   - Security group: `nextjs-alb-sg`
   - Listener: HTTP:80 → Forward to `nextjs-blog-tg`

### Step 7: Create Launch Template

1. Go to: EC2 → Launch Templates → Create launch template

2. Configuration:
   - Name: `nextjs-blog-launch-template`
   - AMI: Select your Golden AMI
   - Instance type: t2.micro (or t3.micro)
   - Key pair: Your key pair
   - Network: Don't include in launch template (will be in ASG)
   - Security group: `nextjs-instance-sg`
   - IAM instance profile: Select the role created in Step 3

3. Advanced details → User data:
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

### Step 8: Create Auto Scaling Group

1. Go to: EC2 → Auto Scaling Groups → Create Auto Scaling group

2. Configuration:
   - Name: `nextjs-blog-asg`
   - Launch template: `nextjs-blog-launch-template`
   - VPC: Your VPC
   - Subnets: Private subnets in multiple AZs
   - Load balancing: Attach to existing load balancer
   - Target group: `nextjs-blog-tg`
   - Health check type: ELB
   - Health check grace period: 300 seconds
   - Desired capacity: 2
   - Minimum capacity: 1
   - Maximum capacity: 4

3. Scaling policies:
   - Target tracking scaling policy
   - Metric: Average CPU utilization
   - Target value: 70%
   - Instance warmup: 300 seconds

4. Tags:
   - Key: `Name`, Value: `nextjs-blog-instance`
   - Key: `Environment`, Value: `production`

### Step 9: Test Deployment

1. Wait for instances to launch and become healthy (5-10 minutes)

2. Check ASG activity:
   ```
   EC2 → Auto Scaling Groups → nextjs-blog-asg → Activity
   ```

3. Check target health:
   ```
   EC2 → Target Groups → nextjs-blog-tg → Targets
   ```

4. Get ALB DNS name:
   ```
   EC2 → Load Balancers → nextjs-blog-alb → DNS name
   ```

5. Test the application:
   ```bash
   # Replace with your ALB DNS
   ALB_DNS="nextjs-blog-alb-xxxxx.region.elb.amazonaws.com"
   
   curl http://$ALB_DNS/api/health
   curl http://$ALB_DNS/
   
   # Open in browser
   open http://$ALB_DNS
   ```

## Troubleshooting

### Instances Not Becoming Healthy

1. SSH into an instance:
   ```bash
   ssh -i your-key.pem ec2-user@instance-ip
   ```

2. Check user data log:
   ```bash
   sudo tail -f /var/log/user-data.log
   ```

3. Check PM2:
   ```bash
   pm2 status
   pm2 logs nextjs-blog
   ```

4. Check NGINX:
   ```bash
   sudo systemctl status nginx
   sudo tail -f /var/log/nginx/error.log
   ```

5. Test locally:
   ```bash
   curl http://localhost:3000
   curl http://localhost/api/health
   ```

### Instance Launch Failures

1. Check launch template user data syntax
2. Verify security group rules allow outbound internet access
3. Check IAM role permissions
4. Review CloudWatch logs if enabled

### High Memory Usage on t2.micro

Add swap space in user data:
```bash
sudo dd if=/dev/zero of=/swapfile bs=128M count=8
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
```

## Updating the Application

### With Golden AMI:

The user data script automatically pulls the latest code from the main branch on every instance launch.

To deploy updates:
1. Push changes to GitHub
2. Terminate instances in ASG (ASG will launch new ones)
3. Or: Manually SSH and run: `/usr/local/bin/deploy-nextjs.sh`

### Creating New AMI Version:

When you need to update infrastructure (Node.js version, system packages):
1. Launch instance from old AMI
2. Make updates
3. Create new AMI (version v2, v3, etc.)
4. Update launch template to use new AMI
5. Instances will use new AMI on next launch

## Best Practices

1. **Use Private Subnets**: Place EC2 instances in private subnets with NAT Gateway
2. **Enable CloudWatch Logs**: Monitor application and system logs
3. **Set Up Alarms**: CPU, memory, unhealthy host count
4. **Use HTTPS**: Add SSL certificate to ALB (AWS Certificate Manager)
5. **Enable Access Logs**: ALB access logs to S3
6. **Version Your AMIs**: Tag with date and version number
7. **Test Scaling**: Manually test scale-in and scale-out events
8. **Use Parameter Store**: Store configuration (repo URL, branch) in SSM Parameter Store
9. **Implement CI/CD**: Use GitHub Actions to automatically create new AMIs on merge

## Cost Optimization

- Use t3.micro instead of t2.micro (better performance per dollar)
- Set appropriate scaling policies to avoid over-provisioning
- Use AWS Auto Scaling predictive scaling for known traffic patterns
- Schedule scaling (scale down during off-hours)
- Review and terminate unused resources

## Security Checklist

- ✅ Instances in private subnets
- ✅ ALB in public subnets
- ✅ Security groups with minimal permissions
- ✅ SSH access restricted to your IP
- ✅ HTTPS enabled on ALB
- ✅ Secrets stored in AWS Secrets Manager (not in code)
- ✅ IAM roles with minimal permissions
- ✅ Regular security updates (rebuild AMI monthly)

## Monitoring

Key metrics to monitor:
- ASG group size and health
- Target group healthy/unhealthy host count
- ALB request count and latency
- EC2 CPU and memory utilization
- Application error rates
- PM2 restart count

## Next Steps

1. Set up custom domain with Route 53
2. Add SSL certificate with AWS Certificate Manager
3. Implement CloudWatch dashboards
4. Set up SNS alerts for failures
5. Implement CI/CD pipeline
6. Add CloudFront CDN for static assets
7. Consider using ECS/Fargate for container-based deployment
