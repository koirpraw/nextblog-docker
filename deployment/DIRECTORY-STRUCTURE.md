# Deployment Directory Organization

This document explains the organization of the `deployment/` directory after reorganization.

## 📁 Directory Structure

```
deployment/
├── README.md                          # Main deployment overview (explains both approaches)
├── DEPLOYMENT-CHECKLIST.md            # General deployment checklist
├── QUICK-REFERENCE.md                 # Quick reference for Node.js/PM2 deployment
├── TROUBLESHOOTING.md                 # Troubleshooting guide (applies to both)
│
├── docker/                            # 🐳 DOCKER-BASED DEPLOYMENT (Recommended)
│   ├── README.md                      # Docker deployment overview
│   ├── STEP-BY-STEP.md               # 👈 START HERE for Docker deployment
│   ├── DOCKER-DEPLOYMENT-GUIDE.md    # Complete Docker guide
│   ├── DOCKER-QUICK-REFERENCE.md     # Quick commands for Docker
│   ├── setup-golden-ami-docker.sh    # Creates Golden AMI with Docker
│   ├── user-data-docker.sh           # Launch Template user-data for Docker
│   └── setup-aws-infrastructure.sh   # Automated AWS setup (ALB, ASG, etc.)
│
└── [Root Level]                       # 📦 NODE.JS/PM2 DEPLOYMENT (Traditional)
    ├── setup-golden-ami.sh            # Creates Golden AMI with Node.js/PM2
    ├── user-data-golden-ami.sh        # User-data for Golden AMI approach
    ├── user-data-full-bootstrap.sh    # User-data for full bootstrap
    ├── diagnose-asg-instance.sh       # Diagnostic script
    ├── fix-nginx-config.sh            # NGINX config fix script
    ├── fix-oom-issue.sh               # Out of memory fix script
    └── iam-policy.json                # Sample IAM policy
```

## 🎯 Which Deployment Approach?

### Use Docker Deployment (`docker/`) if:
- ✅ You want modern containerized deployment
- ✅ You need faster instance launch times (~2-3 min)
- ✅ You want easier updates and maintenance
- ✅ You're deploying to production

**Start with**: [`docker/STEP-BY-STEP.md`](docker/STEP-BY-STEP.md)

### Use Node.js/PM2 Deployment (root) if:
- ✅ You're learning AWS fundamentals
- ✅ You prefer traditional deployment
- ✅ You don't want to use Docker
- ✅ You're working with legacy systems

**Start with**: [`README.md`](README.md)

## 🔄 Migration from Old Structure

If you have old references to files, here's the mapping:

| Old Location | New Location |
|--------------|--------------|
| `deployment/setup-golden-ami-docker.sh` | `deployment/docker/setup-golden-ami-docker.sh` |
| `deployment/user-data-docker.sh` | `deployment/docker/user-data-docker.sh` |
| `deployment/setup-aws-infrastructure.sh` | `deployment/docker/setup-aws-infrastructure.sh` |
| `deployment/DOCKER-DEPLOYMENT-GUIDE.md` | `deployment/docker/DOCKER-DEPLOYMENT-GUIDE.md` |
| `deployment/DOCKER-QUICK-REFERENCE.md` | `deployment/docker/DOCKER-QUICK-REFERENCE.md` |
| `deployment/STEP-BY-STEP.md` | `deployment/docker/STEP-BY-STEP.md` |

## 📋 File Purposes

### Docker Directory Files

| File | Purpose | When to Use |
|------|---------|-------------|
| `README.md` | Overview of Docker deployment | First read |
| `STEP-BY-STEP.md` | Action plan with exact commands | During deployment |
| `DOCKER-DEPLOYMENT-GUIDE.md` | Comprehensive reference | Deep dive, troubleshooting |
| `DOCKER-QUICK-REFERENCE.md` | Quick commands cheat sheet | Daily operations |
| `setup-golden-ami-docker.sh` | Creates Golden AMI | Once, or when updating AMI |
| `user-data-docker.sh` | Starts app on instance boot | Used in Launch Template |
| `setup-aws-infrastructure.sh` | Creates AWS resources | Once, or when rebuilding infra |

### Root Directory Files (Node.js/PM2)

| File | Purpose | When to Use |
|------|---------|-------------|
| `README.md` | Overview of Node.js deployment | First read |
| `setup-golden-ami.sh` | Creates Golden AMI with Node.js | Once, or when updating AMI |
| `user-data-golden-ami.sh` | Minimal user-data for Golden AMI | Used in Launch Template |
| `user-data-full-bootstrap.sh` | Full bootstrap without Golden AMI | Testing, simple deployments |
| `diagnose-asg-instance.sh` | Debug running instances | Troubleshooting |
| `fix-nginx-config.sh` | Fix NGINX configuration | When NGINX issues occur |
| `fix-oom-issue.sh` | Fix out-of-memory issues | When npm install fails |

### Shared Files

| File | Purpose | Applies To |
|------|---------|-----------|
| `TROUBLESHOOTING.md` | Common issues and solutions | Both approaches |
| `DEPLOYMENT-CHECKLIST.md` | Pre-deployment checklist | Both approaches |
| `iam-policy.json` | Sample IAM permissions | Both approaches |

## 🚀 Quick Start

**For Docker deployment** (Recommended):
```bash
cd deployment/docker
cat STEP-BY-STEP.md
# Follow the guide step by step
```

**For Node.js/PM2 deployment**:
```bash
cd deployment
cat README.md
# Follow the guide
```

## 🔧 Updating Scripts

If you need to update repository URLs or configurations:

**Docker deployment**:
- Edit `deployment/docker/setup-golden-ami-docker.sh` (line 75)
- Edit `deployment/docker/setup-aws-infrastructure.sh` (line 11 for AMI ID)

**Node.js/PM2 deployment**:
- Edit `deployment/setup-golden-ami.sh`

## 📝 Notes

- **All scripts have execute permissions** (`chmod +x` applied)
- **Docker directory is self-contained** - all Docker-related files are together
- **No duplicate files** - each deployment approach has its own scripts
- **Clear separation** - prevents mixing Docker and Node.js commands

---

**Need help?** Check the appropriate README:
- Docker: [`docker/README.md`](docker/README.md)
- Node.js/PM2: [`README.md`](README.md)
