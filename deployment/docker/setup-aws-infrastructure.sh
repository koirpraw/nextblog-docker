#!/bin/bash
# AWS Infrastructure Setup Script for Next.js ASG + ALB Deployment
# This script provides AWS CLI commands to set up the complete infrastructure
# Run these commands step by step, not all at once

set -e

# ============================================
# CONFIGURATION - UPDATE THESE VALUES
# ============================================

REGION="us-east-1"
KEY_NAME="sandbox-ec2-key"
SECURITY_GROUP_NAME="WebServer-SG"
AMI_ID="ami-XXXXXXXXX"  # Your Golden AMI ID (create this first)
INSTANCE_TYPE="t3.micro"  # or t2.micro for free tier
VPC_ID=""  # Will be auto-detected or set manually
SUBNET_1=""  # Will be auto-detected or set manually
SUBNET_2=""  # Will be auto-detected or set manually

echo "=========================================="
echo "AWS Infrastructure Setup for Next.js Blog"
echo "=========================================="
echo ""

# ============================================
# STEP 1: Get VPC and Subnets
# ============================================

echo "Step 1: Getting VPC and Subnets..."
echo ""

# Get default VPC
if [ -z "$VPC_ID" ]; then
    VPC_ID=$(aws ec2 describe-vpcs \
        --region $REGION \
        --filters "Name=isDefault,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text)
    echo "Default VPC: $VPC_ID"
fi

# Get subnets in different AZs
if [ -z "$SUBNET_1" ]; then
    SUBNET_1=$(aws ec2 describe-subnets \
        --region $REGION \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=default-for-az,Values=true" \
        --query 'Subnets[0].SubnetId' \
        --output text)
    echo "Subnet 1: $SUBNET_1"
fi

if [ -z "$SUBNET_2" ]; then
    SUBNET_2=$(aws ec2 describe-subnets \
        --region $REGION \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=default-for-az,Values=true" \
        --query 'Subnets[1].SubnetId' \
        --output text)
    echo "Subnet 2: $SUBNET_2"
fi

# Get Security Group ID
SG_ID=$(aws ec2 describe-security-groups \
    --region $REGION \
    --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)
echo "Security Group: $SG_ID"

echo ""
echo "⚠️  IMPORTANT: Before proceeding, ensure:"
echo "   1. You have created the Golden AMI (run setup-golden-ami-docker.sh)"
echo "   2. Update AMI_ID variable above with your Golden AMI ID"
echo "   3. Your Security Group ($SECURITY_GROUP_NAME) allows:"
echo "      - Port 80 (HTTP) from 0.0.0.0/0 (for ALB)"
echo "      - Port 22 (SSH) from your IP (for debugging)"
echo ""
read -p "Press Enter to continue or Ctrl+C to abort..."

# ============================================
# STEP 2: Create Target Group
# ============================================

echo ""
echo "Step 2: Creating Target Group..."

TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
    --region $REGION \
    --name nextjs-blog-tg \
    --protocol HTTP \
    --port 80 \
    --vpc-id $VPC_ID \
    --health-check-enabled \
    --health-check-protocol HTTP \
    --health-check-path /api/health \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3 \
    --matcher HttpCode=200 \
    --target-type instance \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

echo "Target Group ARN: $TARGET_GROUP_ARN"

# Configure target group attributes
aws elbv2 modify-target-group-attributes \
    --region $REGION \
    --target-group-arn $TARGET_GROUP_ARN \
    --attributes \
        Key=deregistration_delay.timeout_seconds,Value=30 \
        Key=stickiness.enabled,Value=true \
        Key=stickiness.type,Value=lb_cookie \
        Key=stickiness.lb_cookie.duration_seconds,Value=86400

echo "✓ Target Group configured"

# ============================================
# STEP 3: Create Application Load Balancer
# ============================================

echo ""
echo "Step 3: Creating Application Load Balancer..."

ALB_ARN=$(aws elbv2 create-load-balancer \
    --region $REGION \
    --name nextjs-blog-alb \
    --subnets $SUBNET_1 $SUBNET_2 \
    --security-groups $SG_ID \
    --scheme internet-facing \
    --type application \
    --ip-address-type ipv4 \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)

echo "ALB ARN: $ALB_ARN"

# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --region $REGION \
    --load-balancer-arns $ALB_ARN \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

echo "ALB DNS Name: $ALB_DNS"
echo ""
echo "⚠️  Save this DNS name! You'll access your app at: http://$ALB_DNS"
echo ""

# Wait for ALB to be active
echo "Waiting for ALB to become active (this may take 2-3 minutes)..."
aws elbv2 wait load-balancer-available \
    --region $REGION \
    --load-balancer-arns $ALB_ARN
echo "✓ ALB is active"

# ============================================
# STEP 4: Create Listener
# ============================================

echo ""
echo "Step 4: Creating ALB Listener..."

LISTENER_ARN=$(aws elbv2 create-listener \
    --region $REGION \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN \
    --query 'Listeners[0].ListenerArn' \
    --output text)

echo "Listener ARN: $LISTENER_ARN"
echo "✓ Listener configured to forward traffic to Target Group"

# ============================================
# STEP 5: Create Launch Template
# ============================================

echo ""
echo "Step 5: Creating Launch Template..."

# Read user data script
USER_DATA=$(base64 -i deployment/docker/user-data-docker.sh)

# Create launch template
aws ec2 create-launch-template \
    --region $REGION \
    --launch-template-name nextjs-blog-lt \
    --version-description "Docker-based Next.js blog v1" \
    --launch-template-data "{
        \"ImageId\": \"$AMI_ID\",
        \"InstanceType\": \"$INSTANCE_TYPE\",
        \"KeyName\": \"$KEY_NAME\",
        \"SecurityGroupIds\": [\"$SG_ID\"],
        \"UserData\": \"$USER_DATA\",
        \"IamInstanceProfile\": {
            \"Name\": \"EC2DefaultRole\"
        },
        \"TagSpecifications\": [{
            \"ResourceType\": \"instance\",
            \"Tags\": [
                {\"Key\": \"Name\", \"Value\": \"nextjs-blog-asg\"},
                {\"Key\": \"Environment\", \"Value\": \"production\"},
                {\"Key\": \"Application\", \"Value\": \"nextjs-blog\"}
            ]
        }],
        \"MetadataOptions\": {
            \"HttpTokens\": \"optional\",
            \"HttpPutResponseHopLimit\": 1
        },
        \"Monitoring\": {
            \"Enabled\": true
        }
    }"

echo "✓ Launch Template created: nextjs-blog-lt"

# ============================================
# STEP 6: Create Auto Scaling Group
# ============================================

echo ""
echo "Step 6: Creating Auto Scaling Group..."

aws autoscaling create-auto-scaling-group \
    --region $REGION \
    --auto-scaling-group-name nextjs-blog-asg \
    --launch-template LaunchTemplateName=nextjs-blog-lt,Version='$Latest' \
    --min-size 1 \
    --max-size 3 \
    --desired-capacity 2 \
    --default-cooldown 300 \
    --health-check-type ELB \
    --health-check-grace-period 300 \
    --vpc-zone-identifier "$SUBNET_1,$SUBNET_2" \
    --target-group-arns $TARGET_GROUP_ARN \
    --tags \
        Key=Name,Value=nextjs-blog-asg,PropagateAtLaunch=true \
        Key=Environment,Value=production,PropagateAtLaunch=true

echo "✓ Auto Scaling Group created"

# Configure scaling policies (optional)
echo ""
echo "Step 7: Configuring Auto Scaling Policies..."

# Target tracking scaling policy based on CPU
aws autoscaling put-scaling-policy \
    --region $REGION \
    --auto-scaling-group-name nextjs-blog-asg \
    --policy-name cpu-target-tracking \
    --policy-type TargetTrackingScaling \
    --target-tracking-configuration "{
        \"PredefinedMetricSpecification\": {
            \"PredefinedMetricType\": \"ASGAverageCPUUtilization\"
        },
        \"TargetValue\": 50.0
    }"

echo "✓ CPU-based scaling policy configured (target: 50%)"

# ============================================
# SUMMARY
# ============================================

echo ""
echo "=========================================="
echo "✓ Infrastructure Setup Complete!"
echo "=========================================="
echo ""
echo "Resources Created:"
echo "  • Target Group: nextjs-blog-tg"
echo "  • Load Balancer: nextjs-blog-alb"
echo "  • Launch Template: nextjs-blog-lt"
echo "  • Auto Scaling Group: nextjs-blog-asg"
echo ""
echo "Application URL:"
echo "  http://$ALB_DNS"
echo ""
echo "What's happening now:"
echo "  1. ASG is launching 2 EC2 instances"
echo "  2. Each instance runs user-data-docker.sh"
echo "  3. Instances register with Target Group"
echo "  4. ALB performs health checks on /api/health"
echo "  5. Once healthy, ALB starts routing traffic"
echo ""
echo "Expected timeline:"
echo "  • Instances launch: ~1 minute"
echo "  • Docker container starts: ~30 seconds"
echo "  • Health checks pass: ~1-2 minutes"
echo "  • Total: ~3-4 minutes"
echo ""
echo "Monitoring commands:"
echo "  # Check ASG status"
echo "  aws autoscaling describe-auto-scaling-groups --region $REGION --auto-scaling-group-names nextjs-blog-asg"
echo ""
echo "  # Check target health"
echo "  aws elbv2 describe-target-health --region $REGION --target-group-arn $TARGET_GROUP_ARN"
echo ""
echo "  # List running instances"
echo "  aws ec2 describe-instances --region $REGION --filters 'Name=tag:Name,Values=nextjs-blog-asg' 'Name=instance-state-name,Values=running'"
echo ""
echo "Cleanup commands (to delete everything):"
echo "  aws autoscaling delete-auto-scaling-group --region $REGION --auto-scaling-group-name nextjs-blog-asg --force-delete"
echo "  aws ec2 delete-launch-template --region $REGION --launch-template-name nextjs-blog-lt"
echo "  aws elbv2 delete-load-balancer --region $REGION --load-balancer-arn $ALB_ARN"
echo "  aws elbv2 delete-target-group --region $REGION --target-group-arn $TARGET_GROUP_ARN"
echo "=========================================="
