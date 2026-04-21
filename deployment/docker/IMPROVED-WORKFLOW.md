# Improved Docker Workflow - Using Pre-built Images

This guide explains the **improved workflow** using pre-built Docker images from Docker Hub. This is **faster, simpler, and more reliable** than building images on EC2 instances.

## 🚀 Why This Approach is Better

### Old Approach (Build on EC2)
```
Local Code → Git Push → EC2 Instance → Build Image (5-10 min) → Create AMI → Deploy
                                        ⚠️ Slow, uses lots of RAM
```

### New Approach (Pull Pre-built Image)
```
Local Code → Build Image (locally/CI) → Push to Docker Hub → EC2 Instance → Pull Image (1-2 min) → Create AMI → Deploy
             ✅ Fast, reliable                                               ✅ Fast, low memory
```

## 📊 Comparison

| Factor | Build on Instance | Pull Pre-built Image |
|--------|------------------|---------------------|
| **Golden AMI creation time** | 10-15 minutes | 3-5 minutes |
| **Memory usage during setup** | 500-800 MB (risky on t3.micro) | <100 MB |
| **Reliability** | Can fail due to OOM/network | Very reliable |
| **CI/CD friendly** | No | Yes ✅ |
| **Version control** | Hard | Easy (Docker tags) |
| **Rollback** | Rebuild AMI | Change image tag |
| **Multi-region** | Rebuild in each region | Pull same image |
| **Updates without new AMI** | No | Yes ✅ (just pull new tag) |

## 🎯 New Workflow Steps

### Phase 0: Build and Push Image (Do Once or in CI/CD)

**On your local machine:**

1. **Build the Docker image**
   ```bash
   cd /path/to/nextblog-docker
   docker build -t your-username/nextjs-blog:latest .
   ```

2. **Test it locally**
   ```bash
   docker run -d -p 3000:3000 --name test-blog your-username/nextjs-blog:latest
   curl http://localhost:3000/api/health
   docker stop test-blog && docker rm test-blog
   ```

3. **Push to Docker Hub**
   ```bash
   # Login to Docker Hub
   docker login
   
   # Push the image
   docker push your-username/nextjs-blog:latest
   
   # Optional: Tag with version
   docker tag your-username/nextjs-blog:latest your-username/nextjs-blog:v1.0.0
   docker push your-username/nextjs-blog:v1.0.0
   ```

**Or use the automated script:**
```bash
cd deployment/docker
./build-and-push.sh
# Update DOCKER_USERNAME in the script first!
```

### Phase 1: Create Golden AMI (Simplified)

**On EC2 instance:**

1. **Update the script with your Docker image**
   ```bash
   # Edit deployment/docker/setup-golden-ami-docker-pull.sh
   # Line 11: DOCKER_IMAGE="your-username/nextjs-blog:latest"
   ```

2. **Run the simplified setup**
   ```bash
   git clone https://github.com/your-username/nextblog-docker.git
   cd nextblog-docker
   sudo ./deployment/docker/setup-golden-ami-docker-pull.sh
   ```

**This takes only 3-5 minutes** (vs 10-15 with building)

3. **Test and create AMI** (same as before)

### Phase 2: Deploy Infrastructure (Same as Before)

Use the same `setup-aws-infrastructure.sh` script.

### Phase 3: Update Application (New Superpower!)

**Without rebuilding AMI:**

```bash
# Option 1: Update via user-data (automatic on new instances)
# Just uncomment the pull latest section in user-data-docker.sh

# Option 2: Update running instances
ssh -i key.pem ec2-user@instance-ip
sudo docker pull your-username/nextjs-blog:latest
sudo docker stop nextjs-blog
sudo docker rm nextjs-blog
sudo /opt/scripts/deploy-app.sh
```

## 📁 New Files

- **[build-and-push.sh](build-and-push.sh)** - Build locally and push to Docker Hub
- **[setup-golden-ami-docker-pull.sh](setup-golden-ami-docker-pull.sh)** - Simplified Golden AMI setup (pulls image instead of building)

## 🔄 Complete Updated Workflow

### Setup (One Time)

```bash
# 1. Create Docker Hub account (free)
https://hub.docker.com/signup

# 2. Build and push your image
cd deployment/docker
nano build-and-push.sh  # Update DOCKER_USERNAME
./build-and-push.sh

# 3. Update Golden AMI script
nano setup-golden-ami-docker-pull.sh  # Update DOCKER_IMAGE (line 11)
```

### Deployment

```bash
# 4. Create Golden AMI (on EC2 instance)
sudo ./deployment/docker/setup-golden-ami-docker-pull.sh

# 5. Create AWS infrastructure (on local machine)
cd deployment/docker
nano setup-aws-infrastructure.sh  # Update AMI_ID
./setup-aws-infrastructure.sh

# Done! Application is running
```

### Updates

```bash
# When you update code:
# 1. Build and push new image
./deployment/docker/build-and-push.sh

# 2. Either:
#    a) Create new Golden AMI (for major updates)
#    b) Update running instances (for quick updates)
#    c) Configure auto-pull in user-data (for automatic updates)
```

## 🎨 Versioning Strategy

### Semantic Versioning
```bash
# Development
docker push your-username/nextjs-blog:dev

# Staging
docker push your-username/nextjs-blog:staging

# Production releases
docker push your-username/nextjs-blog:v1.0.0
docker push your-username/nextjs-blog:v1.0.1
docker push your-username/nextjs-blog:latest  # Always points to latest stable
```

### In Golden AMI
```bash
# Production (stable)
DOCKER_IMAGE="your-username/nextjs-blog:latest"

# Specific version (immutable)
DOCKER_IMAGE="your-username/nextjs-blog:v1.0.0"

# Development (auto-update)
DOCKER_IMAGE="your-username/nextjs-blog:dev"
```

## 🔧 Configuration Options

### Auto-Update on Instance Launch

Enable in `deployment/docker/user-data-docker.sh`:

```bash
# Uncomment these lines to pull latest image on every instance launch
echo "Pulling latest application code..."
sudo docker pull your-username/nextjs-blog:latest
sudo docker tag your-username/nextjs-blog:latest nextjs-blog:latest
```

**When to use:**
- ✅ Development/staging environments
- ✅ When you want rolling updates automatically
- ❌ Production (use specific version tags for stability)

### Manual Update Process

For production, control updates manually:

```bash
# SSH into instance
ssh -i key.pem ec2-user@instance-ip

# Pull new version
sudo docker pull your-username/nextjs-blog:v1.1.0

# Test it
sudo docker run --rm your-username/nextjs-blog:v1.1.0 node -v

# Deploy
sudo docker tag your-username/nextjs-blog:v1.1.0 nextjs-blog:latest
sudo /opt/scripts/deploy-app.sh
```

## 🔒 Private Docker Registries

If you prefer private images:

### Docker Hub Private Repository

```bash
# On EC2 instance, before pulling
echo "YOUR_DOCKER_PASSWORD" | sudo docker login -u YOUR_USERNAME --password-stdin

# Then pull as usual
sudo docker pull your-username/nextjs-blog:latest
```

### Amazon ECR (Recommended for AWS)

```bash
# 1. Create ECR repository
aws ecr create-repository --repository-name nextjs-blog --region us-east-1

# 2. Get login token
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin YOUR_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com

# 3. Tag and push
docker tag nextjs-blog:latest YOUR_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/nextjs-blog:latest
docker push YOUR_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/nextjs-blog:latest

# 4. In setup script, use ECR image
DOCKER_IMAGE="YOUR_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/nextjs-blog:latest"
```

## 📈 CI/CD Integration

### GitHub Actions Example

```yaml
name: Build and Push Docker Image

on:
  push:
    branches: [ main ]
    tags: [ 'v*' ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Login to Docker Hub
        uses: docker/login-action@v2
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}
      
      - name: Build and push
        uses: docker/build-push-action@v4
        with:
          context: .
          push: true
          tags: |
            your-username/nextjs-blog:latest
            your-username/nextjs-blog:${{ github.sha }}
```

Then instances auto-pull on launch!

## 🎯 Benefits Summary

✅ **Faster Golden AMI creation** - 3-5 min instead of 10-15 min
✅ **Lower memory usage** - No build step on t3.micro
✅ **More reliable** - No build failures
✅ **Better versioning** - Use Docker tags
✅ **Easy rollback** - Just change image tag
✅ **CI/CD ready** - Build in pipeline
✅ **Multi-region** - Same image everywhere
✅ **Update without AMI rebuild** - Pull new tag

## 🔄 Migration from Old Approach

If you're currently using `setup-golden-ami-docker.sh`:

1. Build and push your current image:
   ```bash
   ./deployment/docker/build-and-push.sh
   ```

2. Use the new script:
   ```bash
   # Instead of: setup-golden-ami-docker.sh
   # Use: setup-golden-ami-docker-pull.sh
   ```

3. That's it! Everything else stays the same.

---

**Recommended**: Use this new approach for all new deployments. It's simpler, faster, and more robust! 🚀
