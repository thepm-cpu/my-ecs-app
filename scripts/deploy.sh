#!/bin/bash
# deploy.sh - Application Deployment Script
# Builds Docker image, creates infrastructure, and deploys to ECS

set -e

echo " ECS Fargate Application Deployment"
echo "===================================="

# Load environment configuration
if [ ! -f ".env" ]; then
    echo " Environment file not found. Run './scripts/bootstrap.sh' first."
    exit 1
fi

source .env

echo " Deployment Configuration:"
echo "  Account ID: $AWS_ACCOUNT_ID"
echo "  Region: $AWS_REGION"
echo "  ECR URI: $ECR_URI"
echo "  ECS Cluster: $CLUSTER_NAME"
echo ""

# Build image tag with timestamp
IMAGE_TAG="$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD 2>/dev/null || echo 'local')"
FULL_IMAGE_URI="$ECR_URI:$IMAGE_TAG"

echo " Step 1: Building Docker Image..."
docker build -t my-ecs-app:latest .
docker tag my-ecs-app:latest $ECR_URI:latest
docker tag my-ecs-app:latest $FULL_IMAGE_URI

echo "✅ Image built and tagged:"
echo "  Latest: $ECR_URI:latest"
echo "  Tagged: $FULL_IMAGE_URI"
echo ""

# Test image locally before pushing
echo " Step 2: Testing image locally..."
echo "Starting test container..."
CONTAINER_ID=$(docker run -d -p 3001:3000 my-ecs-app:latest)
sleep 3

# Test health endpoint
if curl -f http://localhost:3001/health >/dev/null 2>&1; then
    echo "✅ Local container health check passed"
else
    echo "❌ Local container health check failed"
    docker logs $CONTAINER_ID
    docker stop $CONTAINER_ID
    exit 1
fi

docker stop $CONTAINER_ID
echo ""

# Push to ECR
echo " Step 3: Pushing to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI

docker push $ECR_URI:latest
docker push $FULL_IMAGE_URI
echo "✅ Images pushed to ECR"
echo ""

# Create/Update task definition
echo " Step 4: Creating ECS Task Definition..."

# Create task definition with current image
cat > /tmp/task-definition.json << EOF
{
  "family": "my-ecs-app",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "$EXECUTION_ROLE_ARN",
  "containerDefinitions": [
    {
      "name": "my-ecs-app",
      "image": "$FULL_IMAGE_URI",
      "cpu": 256,
      "memory": 512,
      "essential": true,
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "$LOG_GROUP_NAME",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "environment": [
        {
          "name": "NODE_ENV",
          "value": "production"
        },
        {
          "name": "PORT",
          "value": "3000"
        },
        {
          "name": "APP_VERSION",
          "value": "$IMAGE_TAG"
        }
      ]
    }
  ]
}
EOF

# Register task definition
TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json file:///tmp/task-definition.json \
    --region $AWS_REGION \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

echo "✅ Task definition registered: $TASK_DEF_ARN"
rm /tmp/task-definition.json
echo ""

# Create networking components
echo " Step 5: Setting up Load Balancer and Networking..."

# Get VPC and subnets
SUBNET1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[0].SubnetId" --output text --region $AWS_REGION)
SUBNET2=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[1].SubnetId" --output text --region $AWS_REGION)
SUBNET_IDS="$SUBNET1,$SUBNET2"

echo "Using subnets: $SUBNET_IDS"

# Create ALB Security Group
ALB_SG_NAME="my-app-alb-sg-$(date +%s)"
ALB_SG=$(aws ec2 create-security-group \
    --group-name $ALB_SG_NAME \
    --description "Security group for ALB" \
    --vpc-id $VPC_ID \
    --region $AWS_REGION \
    --query "GroupId" --output text)

aws ec2 authorize-security-group-ingress \
    --group-id $ALB_SG \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION

echo "✅ ALB Security Group: $ALB_SG"

# Create ECS Security Group
ECS_SG_NAME="my-ecs-tasks-sg-$(date +%s)"
ECS_SG=$(aws ec2 create-security-group \
    --group-name $ECS_SG_NAME \
    --description "Security group for ECS tasks" \
    --vpc-id $VPC_ID \
    --region $AWS_REGION \
    --query "GroupId" --output text)

# Allow traffic from ALB to ECS tasks
aws ec2 authorize-security-group-ingress \
    --group-id $ECS_SG \
    --protocol tcp \
    --port 3000 \
    --source-group $ALB_SG \
    --region $AWS_REGION

echo "✅ ECS Security Group: $ECS_SG"

# Create Application Load Balancer
ALB_NAME="my-app-alb-$(date +%s)"
ALB_ARN=$(aws elbv2 create-load-balancer \
    --name $ALB_NAME \
    --subnets $SUBNET1 $SUBNET2 \
    --security-groups $ALB_SG \
    --region $AWS_REGION \
    --query "LoadBalancers[0].LoadBalancerArn" --output text)

# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns $ALB_ARN \
    --region $AWS_REGION \
    --query "LoadBalancers[0].DNSName" --output text)

echo "✅ ALB Created: $ALB_DNS"

# Create Target Group
TG_NAME="my-app-targets-$(date +%s)"
TG_ARN=$(aws elbv2 create-target-group \
    --name $TG_NAME \
    --protocol HTTP \
    --port 3000 \
    --vpc-id $VPC_ID \
    --target-type ip \
    --health-check-enabled \
    --health-check-path /health \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3 \
    --region $AWS_REGION \
    --query "TargetGroups[0].TargetGroupArn" --output text)

echo "✅ Target Group Created: $TG_ARN"

# Create Listener
aws elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=$TG_ARN \
    --region $AWS_REGION >/dev/null

echo "✅ Listener created and configured"
echo ""

# Create ECS Service
echo "  Step 6: Creating ECS Service..."
SERVICE_NAME="my-app-service"

aws ecs create-service \
    --cluster $CLUSTER_NAME \
    --service-name $SERVICE_NAME \
    --task-definition $TASK_DEF_ARN \
    --desired-count 2 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$ECS_SG],assignPublicIp=ENABLED}" \
    --load-balancers "targetGroupArn=$TG_ARN,containerName=my-ecs-app,containerPort=3000" \
    --health-check-grace-period-seconds 120 \
    --region $AWS_REGION >/dev/null

echo "✅ ECS Service '$SERVICE_NAME' created"
echo ""

# Update environment with deployment info
cat >> .env << EOF

# Deployment Information
SERVICE_NAME=$SERVICE_NAME
TASK_DEF_ARN=$TASK_DEF_ARN
ALB_ARN=$ALB_ARN
ALB_DNS=$ALB_DNS
TG_ARN=$TG_ARN
ALB_SG=$ALB_SG
ECS_SG=$ECS_SG
IMAGE_TAG=$IMAGE_TAG
EOF

echo " Deployment Initiated!"
echo "======================"
echo "✅ Docker Image: $FULL_IMAGE_URI"
echo "✅ ECS Service: $SERVICE_NAME"
echo "✅ Task Definition: $TASK_DEF_ARN"
echo "✅ Load Balancer: $ALB_DNS"
echo "✅ Target Group: $TG_ARN"
echo ""
echo " Deployment Status:"
echo "   The service is starting up. This takes 3-5 minutes."
echo ""
echo " Monitor Progress:"
echo "   aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION"
echo ""
echo " Test When Ready (wait 3-5 minutes):"
echo "   curl http://$ALB_DNS/health"
echo "   curl http://$ALB_DNS/"
echo "   curl http://$ALB_DNS/api/info"
echo ""
echo " View Logs:"
echo "   aws logs tail $LOG_GROUP_NAME --follow --region $AWS_REGION"
echo ""
echo " Cleanup When Done:"
echo "   ./scripts/cleanup.sh"
echo ""
echo " Cost Note: ALB (~$16/month) + Fargate (~$0.05/hour per task)"
echo "   Resources will continue charging until cleaned up!"

# Wait and show initial status
echo ""
echo " Waiting 30 seconds for initial service status..."
sleep 30

aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --region $AWS_REGION \
    --query 'services[0].[serviceName,status,runningCount,desiredCount]' \
    --output table