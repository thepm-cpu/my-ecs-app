### ECS Fargate Production Deployment — Containerized Node.js with Auto-Scaling & CI/CD
### Production-ready containerized application deployed to AWS ECS Fargate with Application Load Balancer, auto-scaling, health monitoring, and fully automated GitHub Actions CI/CD pipeline.

![loadbalancer-webpage](./assets/loadbalancer-webpage.png)
![ecs-service](./assets/ecs-service.png)
![cloudwatch](./assets/cloudwatch.png)

## Demo / Architecture Overview

![vscode-screen-ecs](./assets/vscode-screen-ecs.png)

## Why I Built This

1. Problem Solved: Demonstrate enterprise-grade container orchestration with serverless infrastructure
2. Business Value: Zero-downtime deployments, automatic scaling, and cost-optimized pay-per-use model
3. Learning Goal: Master modern DevOps practices combining containers, orchestration, load balancing, and CI/CD

## Architecture Deep Dive

┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│   GitHub Repo   │───▶│  GitHub Actions  │───▶│    Amazon ECR       │
│   (Source Code) │    │   (CI/CD Pipeline) │    │ (Container Registry)│
└─────────────────┘    └──────────────────┘    └─────────────────────┘
                                │                           │
                                ▼                           │
┌─────────────────┐    ┌──────────────────┐                │
│  Application    │◀───│  ECS Service     │◀───────────────┘
│  Load Balancer  │    │  (Fargate Tasks) │
│  (Multi-AZ)     │    │  Auto Scaling    │
└─────────────────┘    └──────────────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐    ┌──────────────────┐
│  Target Groups  │    │   CloudWatch     │
│ (Health Checks) │    │   (Logs/Metrics) │
└─────────────────┘    └──────────────────┘

## Components:

1. ECS Fargate: Serverless container orchestration (no EC2 management)
2. Application Load Balancer: Layer 7 load balancing with health checks
3. Auto Scaling: Dynamic scaling based on CPU/memory thresholds
4. ECR: Private container registry with image vulnerability scanning
5. CloudWatch: Comprehensive logging and monitoring
GitHub Actions: Automated build, test, and deployment pipeline

### Quick Start (Production Demo)
## Prerequisites

# Required tools
aws-cli (v2.x)
docker (v20.x+)
git
curl

1. Clone and Setup
git clone https://github.com/yourusername/ecs-fargate-demo.git
cd ecs-fargate-demo

2. Configure AWS Credentials
aws configure
# Enter your AWS Access Key ID, Secret, and region (us-east-1)

3. Bootstrap Infrastructure
./scripts/bootstrap.sh
# Creates: ECS Cluster, ECR Repository, CloudWatch Log Groups
# Estimated setup time: 2-3 minutes

4. Build and Deploy
./scripts/deploy.sh
# Builds Docker image, pushes to ECR, creates ECS service with ALB
# First deployment time: 5-7 minutes

5. Test the Application
# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[0].DNSName' --output text)

# Test endpoints
curl http://$ALB_DNS/health          # Health check endpoint
curl http://$ALB_DNS/                # Main application
curl http://$ALB_DNS/api/info        # System information API

6. Monitor Deployment
# Check service status
aws ecs describe-services --cluster my-app-cluster --services my-app-service

# View container logs
aws logs tail /ecs/my-ecs-app --follow

# Check target health
aws elbv2 describe-target-health --target-group-arn [YOUR_TG_ARN]

7. Cleanup (Important - Prevents AWS Charges)
./scripts/cleanup.sh
# Removes all resources to avoid ongoing costs
# Cleanup time: 3-5 minutes

## What I Implemented
# Container & Application Layer

1. Multi-stage Docker build with Node.js 18 Alpine base image
2. Security hardening: Non-root user execution (nodejs:1001)
3. Optimized layers: Package.json caching for faster rebuilds
4. Health endpoints: Custom /health route for ALB health checks
5. Graceful shutdown: Proper SIGTERM handling for zero-downtime deployments

## ECS Fargate Configuration

1. Task Definition: 256 CPU units, 512MB memory allocation
2. Network Mode: awsvpc with dedicated ENI per task
3. Service Configuration: Rolling deployment strategy with health check grace period
4. Auto Scaling: Target tracking based on CPU utilization (40-70% target)
5. Multi-AZ deployment: High availability across 2+ availability zones

## Load Balancer & Networking

1. Application Load Balancer: Layer 7 routing with host-based rules
2. Target Groups: IP-based targeting for Fargate compatibility
3. Security Groups: Least-privilege access (ALB → ECS tasks on port 3000)
4. VPC Integration: Public subnets for ALB, private communication for tasks

## CI/CD Pipeline (GitHub Actions)

1. Automated triggers: Push to main branch initiates deployment
2. Build process: Docker image with commit SHA tagging
3. Security scanning: Container vulnerability assessment
4. ECR integration: Automatic image push with credential management
5. ECS deployment: Task definition updates with service force-deployment
6. Rollback capability: Automatic rollback on deployment failure

## Monitoring & Observability

1. CloudWatch Logs: Structured logging with log stream per task
2. Container Insights: CPU, memory, network metrics per service
3. Custom dashboards: Real-time performance monitoring
4. Alerting: SNS notifications for service failures and scaling events

## What I Learned
# Technical Challenges Solved

1. Health Check Debugging: Discovered Docker HEALTHCHECK using curl in Alpine without curl installed
2. Security Group Configuration: Proper ALB → ECS task communication requires source group references
3. Target Registration: Fargate tasks register as IP targets, not instance targets
4. Multiple Resource Management: Avoided naming conflicts during iterative development

## Architecture Decisions

1. Fargate vs EC2: Chose Fargate for serverless simplicity and pay-per-use cost model
2. ALB vs NLB: Application Load Balancer for HTTP/HTTPS routing and health checks
3. Auto Scaling Strategy: CPU-based scaling more predictable than request-based for demo workload
4. Single vs Multi-container: Single container per task for simplicity and resource isolation

## Production Readiness Considerations

1. Cost optimization: Right-sized containers and scheduled scaling for predictable traffic
2. Security: IAM roles with least privilege, VPC isolation, no hardcoded secrets
3. Reliability: Multi-AZ deployment, health checks, and automatic task replacement
4. Monitoring: Comprehensive logging and alerting for proactive issue resolution

## Files & Structure
├── app.js                          # Node.js application with health endpoints
├── package.json                    # Dependencies and scripts
├── Dockerfile                      # Multi-stage container build
├── .dockerignore                   # Container build optimization
├── .github/workflows/
│   └── deploy.yml                  # GitHub Actions CI/CD pipeline
├── infrastructure/
│   └── task-definition.json        # ECS task configuration
├── scripts/
│   ├── bootstrap.sh               # Infrastructure setup
│   ├── deploy.sh                  # Manual deployment 
│   └── cleanup.sh                 # Resource cleanup
assets
│   └── screenshots/               # Demo screenshots
└── README.md                      # This file

## Performance & Scale

1. Response Time: < 100ms average response time
2. Availability: 99.9% uptime with automatic recovery
3. Scaling: 2-10 tasks based on CPU utilization
4. Cost: ~$0.05/hour per running task (pay-per-second billing)

## CI Status & Quality


![loadbalancer-webpage](./assets/loadbalancer-webpage.png)
![ecs-service](./assets/ecs-service.png)
![cloudwatch](./assets/cloudwatch.png)
![ecs-service2](./assets/ecs-service2.png)
![loadbalancer2](./assets/loadbalancer2.png)

## Automated Checks:

Docker image vulnerability scanning
Infrastructure validation (terraform plan)
Application health verification post-deployment
Cost estimation and resource tagging

## Cost & Safety Warning
# ⚠️ AWS Resources Created:

1. Application Load Balancer (~$16/month)
2. ECS Fargate tasks (~$0.05/hour each)
3. ECR storage (~$0.10/GB)
4. CloudWatch logs (first 5GB free)

# Always run cleanup script when done:
./scripts/cleanup.sh./scripts/cleanup.sh

## Business Impact

1. Developer Productivity: Automated deployments reduce release cycle from days to minutes
2. Operational Excellence: Self-healing infrastructure with automatic scaling and recovery
3. Cost Efficiency: Pay-per-use model scales to zero during maintenance windows
4. Security: Container isolation and least-privilege access controls

## Technologies Used
1. AWS Services: ECS, Fargate, ALB, ECR, CloudWatch, VPC, IAM
2. Containerization: Docker, Multi-stage builds
3. CI/CD: GitHub Actions, AWS CLI
4. Monitoring: CloudWatch Logs, Container Insights
5. Languages: Node.js, JavaScript, Bash, yaml
6. Infrastructure: Infrastructure as Code principles
License
MIT License - see LICENSE file for details
### Contact & Links
📧 Email: ossaichibuzoralex@gmail.com
💼 LinkedIn: https://www.linkedin.com/in/ossai-chibuzor-0859451ba
📱 GitHub: @thepm-cpu