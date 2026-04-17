# AWS ASG Deployment Checklist

Use this checklist to track your progress through the deployment.

## Important: Amazon Linux Version

**⚠️ These scripts require Amazon Linux 2023 (AL2023)**
- Use AMI: `Amazon Linux 2023 AMI` (e.g., `ami-098e39bafa7e7303d`)
- Not compatible with Amazon Linux 2 without modifications

## Pre-Deployment

- [ ] Have AWS account with appropriate permissions
- [ ] Have EC2 key pair created and downloaded
- [ ] Have VPC with:
  - [ ] At least 2 public subnets in different AZs
  - [ ] At least 2 private subnets in different AZs (recommended)
  - [ ] NAT Gateway in public subnet (if using private subnets)
  - [ ] Internet Gateway attached to VPC
- [ ] Have GitHub repository with Next.js application
- [ ] Health check endpoint created (`/api/health`)
- [ ] Application builds successfully (`npm run build`)
- [ ] Application pushed to GitHub

## Phase 1: Create Golden AMI

- [ ] Launch base EC2 instance (Amazon Linux 2023, t2.micro or t3.micro)
- [ ] Connect security group with SSH access from your IP
- [ ] SSH into the instance
- [ ] Update repository URL in `deployment/setup-golden-ami.sh`
- [ ] Download the setup script on EC2 instance
- [ ] Run `./setup-golden-ami.sh`
- [ ] Update repository URL in `/usr/local/bin/deploy-nextjs.sh`
- [ ] Test deployment: `/usr/local/bin/deploy-nextjs.sh`
- [ ] Verify application:
  - [ ] `pm2 status` shows app running
  - [ ] `curl http://localhost:3000` works
  - [ ] `curl http://localhost/api/health` returns 200
- [ ] Clean up for AMI creation:
  - [ ] Stop PM2 processes: `pm2 delete all`
  - [ ] Remove `.git`: `sudo rm -rf /opt/nextjs-app/.git`
  - [ ] Remove `node_modules`: `sudo rm -rf /opt/nextjs-app/node_modules`
  - [ ] Remove `.next`: `sudo rm -rf /opt/nextjs-app/.next`
  - [ ] Clear history: `history -c`
- [ ] Create AMI from AWS Console
  - [ ] Name: `nextjs-blog-golden-ami-v1`
  - [ ] Add description with version and date
- [ ] Wait for AMI to be available
- [ ] Note AMI ID: `ami-_________________`

## Phase 2: IAM Setup (Optional but Recommended)

- [ ] Create IAM role: `NextjsBlogInstanceRole`
- [ ] Attach policy: `CloudWatchAgentServerPolicy`
- [ ] Attach policy: `AmazonSSMManagedInstanceCore`
- [ ] Attach custom policy from `deployment/iam-policy.json`
- [ ] Save role ARN: `_________________________________`

## Phase 3: Security Groups

### ALB Security Group
- [ ] Create security group: `nextjs-alb-sg`
- [ ] Description: "Security group for Next.js blog ALB"
- [ ] VPC: Select your VPC
- [ ] Inbound rules:
  - [ ] HTTP (80) from 0.0.0.0/0
  - [ ] HTTPS (443) from 0.0.0.0/0
- [ ] Note ALB SG ID: `sg-_________________`

### Instance Security Group
- [ ] Create security group: `nextjs-instance-sg`
- [ ] Description: "Security group for Next.js blog instances"
- [ ] VPC: Select your VPC
- [ ] Inbound rules:
  - [ ] HTTP (80) from ALB Security Group (`sg-_________________`)
  - [ ] SSH (22) from Your IP
- [ ] Outbound rules:
  - [ ] All traffic to 0.0.0.0/0
- [ ] Note Instance SG ID: `sg-_________________`

## Phase 4: Target Group

- [ ] Navigate to: EC2 → Target Groups → Create target group
- [ ] Target type: Instances
- [ ] Target group name: `nextjs-blog-tg`
- [ ] Protocol: HTTP
- [ ] Port: 80
- [ ] VPC: Select your VPC
- [ ] Protocol version: HTTP1
- [ ] Health check settings:
  - [ ] Protocol: HTTP
  - [ ] Path: `/api/health`
  - [ ] Port: Traffic port
  - [ ] Healthy threshold: 2
  - [ ] Unhealthy threshold: 3
  - [ ] Timeout: 5 seconds
  - [ ] Interval: 30 seconds
  - [ ] Success codes: 200
- [ ] Create target group (don't register targets)
- [ ] Note Target Group ARN: `_________________________________`

## Phase 5: Application Load Balancer

- [ ] Navigate to: EC2 → Load Balancers → Create Load Balancer
- [ ] Choose: Application Load Balancer
- [ ] Basic Configuration:
  - [ ] Name: `nextjs-blog-alb`
  - [ ] Scheme: Internet-facing
  - [ ] IP address type: IPv4
- [ ] Network mapping:
  - [ ] VPC: Select your VPC
  - [ ] Mappings: Select at least 2 availability zones
  - [ ] Subnets: Select public subnets
- [ ] Security groups:
  - [ ] Remove default
  - [ ] Select: `nextjs-alb-sg`
- [ ] Listeners and routing:
  - [ ] Protocol: HTTP
  - [ ] Port: 80
  - [ ] Default action: Forward to `nextjs-blog-tg`
- [ ] Create load balancer
- [ ] Wait for ALB to become active
- [ ] Note ALB DNS: `_________________________________`

## Phase 6: Launch Template

- [ ] Navigate to: EC2 → Launch Templates → Create launch template
- [ ] Launch template name: `nextjs-blog-launch-template`
- [ ] Template version description: `v1 - Initial version`
- [ ] Application and OS Images:
  - [ ] My AMIs
  - [ ] Select your Golden AMI: `nextjs-blog-golden-ami-v1`
- [ ] Instance type: `t2.micro` (or `t3.micro`)
- [ ] Key pair: Select your key pair
- [ ] Network settings:
  - [ ] Don't include in launch template (will be set in ASG)
- [ ] Security groups:
  - [ ] Select existing: `nextjs-instance-sg`
- [ ] Advanced details:
  - [ ] IAM instance profile: Select `NextjsBlogInstanceRole`
  - [ ] User data: Copy from `deployment/user-data-golden-ami.sh`
- [ ] Create launch template

## Phase 7: Auto Scaling Group

- [ ] Navigate to: EC2 → Auto Scaling Groups → Create Auto Scaling group
- [ ] Step 1: Choose launch template
  - [ ] Name: `nextjs-blog-asg`
  - [ ] Launch template: `nextjs-blog-launch-template`
  - [ ] Version: Latest
- [ ] Step 2: Choose instance launch options
  - [ ] VPC: Select your VPC
  - [ ] Availability Zones and subnets: Select private subnets in multiple AZs
- [ ] Step 3: Configure advanced options
  - [ ] Load balancing:
    - [ ] Attach to an existing load balancer
    - [ ] Choose from your load balancer target groups
    - [ ] Select: `nextjs-blog-tg`
  - [ ] Health checks:
    - [ ] Turn on ELB health checks
    - [ ] Health check grace period: `300` seconds
  - [ ] Monitoring:
    - [ ] Enable group metrics collection within CloudWatch
- [ ] Step 4: Configure group size and scaling
  - [ ] Desired capacity: `2`
  - [ ] Minimum capacity: `1`
  - [ ] Maximum capacity: `4`
  - [ ] Scaling policies:
    - [ ] Target tracking scaling policy
    - [ ] Scaling policy name: `cpu-scaling-policy`
    - [ ] Metric type: Average CPU utilization
    - [ ] Target value: `70`
    - [ ] Instance warmup: `300` seconds
- [ ] Step 5: Add notifications (optional)
  - [ ] Add SNS topic for scaling events
- [ ] Step 6: Add tags
  - [ ] Key: `Name`, Value: `nextjs-blog-instance`, Tag new instances: Yes
  - [ ] Key: `Environment`, Value: `production`, Tag new instances: Yes
  - [ ] Key: `Application`, Value: `nextjs-blog`, Tag new instances: Yes
- [ ] Step 7: Review and create
- [ ] Create Auto Scaling group

## Phase 8: Testing & Verification

- [ ] Monitor ASG activity:
  - [ ] EC2 → Auto Scaling Groups → `nextjs-blog-asg` → Activity
  - [ ] Wait for instances to launch (5-10 minutes)
- [ ] Monitor target health:
  - [ ] EC2 → Target Groups → `nextjs-blog-tg` → Targets
  - [ ] Wait for targets to become "healthy"
- [ ] If instances not healthy, SSH and troubleshoot:
  - [ ] Get instance IP from EC2 console
  - [ ] SSH: `ssh -i your-key.pem ec2-user@instance-ip`
  - [ ] Check user data: `sudo tail -f /var/log/user-data.log`
  - [ ] Check PM2: `pm2 status && pm2 logs`
  - [ ] Check NGINX: `sudo systemctl status nginx`
  - [ ] Test locally: `curl http://localhost:3000 && curl http://localhost/api/health`
- [ ] Test via ALB:
  - [ ] Health check: `curl http://YOUR-ALB-DNS/api/health`
  - [ ] Home page: `curl http://YOUR-ALB-DNS/`
  - [ ] Admin page: `curl http://YOUR-ALB-DNS/admin`
- [ ] Test in browser:
  - [ ] Open: `http://YOUR-ALB-DNS`
  - [ ] Navigate to different pages
  - [ ] Refresh multiple times (should hit different instances)
- [ ] Test load balancing:
  ```bash
  for i in {1..20}; do curl -s http://YOUR-ALB-DNS/ | grep -o '<title>.*</title>'; done
  ```

## Phase 9: Monitoring Setup (Recommended)

- [ ] Create CloudWatch Dashboard
- [ ] Add widgets for key metrics:
  - [ ] ASG: GroupDesiredCapacity, GroupInServiceInstances
  - [ ] ALB: TargetResponseTime, RequestCount, HealthyHostCount
  - [ ] EC2: CPUUtilization, NetworkIn, NetworkOut
- [ ] Create CloudWatch Alarms:
  - [ ] Unhealthy hosts >= 1
  - [ ] CPU utilization >= 80%
  - [ ] 5XX errors >= 10
  - [ ] No healthy hosts
- [ ] Set up SNS topic and subscribe email for alerts
- [ ] Test alarms by triggering conditions

## Phase 10: Additional Configurations (Optional)

- [ ] Set up custom domain:
  - [ ] Create Route 53 hosted zone
  - [ ] Add A record (alias) pointing to ALB
  - [ ] Update ALB listener rules for domain
- [ ] Add SSL/TLS certificate:
  - [ ] Request certificate from AWS Certificate Manager
  - [ ] Validate domain ownership
  - [ ] Add HTTPS listener to ALB
  - [ ] Update security group for port 443
  - [ ] Add redirect rule: HTTP → HTTPS
- [ ] Enable ALB access logs:
  - [ ] Create S3 bucket for logs
  - [ ] Enable access logs on ALB
- [ ] Set up CloudWatch Logs:
  - [ ] Install CloudWatch agent on Golden AMI
  - [ ] Configure logs: user-data, PM2, NGINX
  - [ ] Create log groups and streams
- [ ] Implement backup strategy:
  - [ ] Tag AMIs for automated cleanup
  - [ ] Set up AMI lifecycle policy
- [ ] Set up CI/CD pipeline:
  - [ ] Create GitHub Actions workflow
  - [ ] Automate AMI creation on merge
  - [ ] Automate ASG instance refresh

## Deployment Complete! 🎉

Your Next.js application is now running in an Auto Scaling Group behind an Application Load Balancer.

### Application URL
- [ ] Note your application URL: `http://_________________________________`

### Important Resources
- [ ] ALB DNS: `_________________________________`
- [ ] Target Group: `nextjs-blog-tg`
- [ ] Auto Scaling Group: `nextjs-blog-asg`
- [ ] Launch Template: `nextjs-blog-launch-template`
- [ ] Golden AMI ID: `ami-_________________`
- [ ] Security Groups: `nextjs-alb-sg`, `nextjs-instance-sg`

### Next Actions
- [ ] Share application URL with team
- [ ] Document deployment process
- [ ] Set up monitoring and alerting
- [ ] Plan for updates and maintenance
- [ ] Consider cost optimization strategies
- [ ] Schedule regular security updates (monthly AMI rebuild)
