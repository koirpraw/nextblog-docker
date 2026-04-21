# Markdown Editor Blog

This is a simple markdown editor blog application built with Next.js, TypeScript, and Tailwind CSS. It allows users to create, edit, and view markdown posts.

## Features

- Create, edit, and delete markdown posts
- Live preview of markdown content
- Syntax highlighting for code blocks
- Responsive design with Tailwind CSS
- Generated posts are saved to the file system

### About this Project
This project is a personal practice project used to learn AWS Development with Next.js. The goal is to learn all different ways to build and run scalable and highly available applications in AWS. The Project builds upon step by step from simpler architectures to more complex ones, starting with a simple Next.js application running on a single EC2 instance, and then ASG with Load Balancer utilizing concepts of Golden AMI, user data and launch templates and so on. Below are the anticipated learning steps:
1. **Next.js on EC2**: Deploy a simple Next.js application on a single EC2 instance.
2. **Auto Scaling Group (ASG)**: Set up an Auto Scaling Group to manage multiple EC2 instances for high availability.
3. **Load Balancing**: Implement a Load Balancer to distribute traffic across multiple instances in the ASG.
4. **Golden AMI**: Create a Golden AMI to ensure consistent application deployment across instances.
5. **User Data and Launch Templates**: Use user data scripts and launch templates to automate instance configuration and application deployment.
6. ASG with Spot Instances: Optimize costs by using Spot Instances in the Auto Scaling Group.
7. **ASG with Dockerized EC2 Instances** ⭐ **[Current Implementation]**: Simplify deployment with Docker containers (optimized for faster launch times and easier updates).
8. ASG- Dockerized step above but using Spot Instances to further optimize costs.

## 🚀 Docker-based ASG + ALB Deployment

**Current implementation uses Docker with Golden AMI for optimized launch times (~2-3 minutes).**

### Quick Start

See the complete guide: **[deployment/docker/DOCKER-DEPLOYMENT-GUIDE.md](deployment/docker/DOCKER-DEPLOYMENT-GUIDE.md)**

**TL;DR:**
1. Create Golden AMI with Docker and pre-built image
2. Set up ALB, Target Group, Launch Template, and ASG
3. Deploy with ~3 minute instance launch time

**Quick Reference:** [deployment/docker/DOCKER-QUICK-REFERENCE.md](deployment/docker/DOCKER-QUICK-REFERENCE.md)

### Key Files

- **[deployment/docker/setup-golden-ami-docker.sh](deployment/docker/setup-golden-ami-docker.sh)**: Creates Golden AMI
- **[deployment/docker/user-data-docker.sh](deployment/docker/user-data-docker.sh)**: Launch Template user-data
- **[deployment/docker/setup-aws-infrastructure.sh](deployment/docker/setup-aws-infrastructure.sh)**: Automated AWS setup
- **[Dockerfile](Dockerfile)**: Optimized multi-stage Docker build


#### Sandbox scope:
- Allowed instances: t3.micro or t2.micro (free tier eligible)
- Maximum instances: 5
- Allowed EC2 AMIs: Amazon Linux 2, Ubuntu 20.04 LTS
- Allowed regions: us-east-1(N. Virginia)
- Allowed EC2 Volume size: 30 GB
- Allowed Volume type: General Purpose SSD (gp2) & General Purpose SSD (gp3)
- Allowed Load Balancer type: Application Load Balancer (ALB), Network Load Balancer (NLB)Amazon Relational 
  
  Database Service (RDS)
1. Allow Create, Update and Delete AWS RDS Instances & Snapshots
2. Allowed Database Engine:  MySQL
3. Allowed Database Instance Type:  db.t3.micro
4. Allowed Database Instance Volume Size:  20 GB
5. Allowed Regions:  N.Virginia (us-east-1)
 
 Amazon S3
1. Allow Create & Delete Amazon S3 Buckets
2. Allow Upload and Delete S3 Objects
3. Allowed S3 Features:
          - Host Static Websites
          - Enable S3 Bucket Versioning
          - Enable S3 Event Notifications
4. Allowed Bucket Region:  N.Virginia (us-east-1)
   
   Amazon Virtual Private Cloud (Amazon VPC)
1. Allow Create, Update and Delete VPC and It's Resources
2. Allow Create Default VPC and Default Subnets
3. Allow Configure Inter-Region Peering
4. Read access to Amazon VPC service
5. Allowed Regions:
          - N.Virginia (us-east-1)
  
Amazon API Gateway
1. Allow Build, Deploy and Delete REST API
2. Allow Build, Deploy and Delete HTTP & Web Socket API
3. Read Access to Amazon API Gateway Service
4. Allowed Region:  N.Virginia (us-east-1)