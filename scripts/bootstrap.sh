#!/bin/bash
# bootstrap.sh - Infrastructure Setup Script
# Creates foundational AWS resources for ECS Fargate deployment

set -e

echo "ECS Fargate Infrastructure Bootstrap"
echo "======================================"
echo "This script creates the foundational AWS resources needed for deployment"
echo ""

# Configuration
REGION=${AWS_REGION:-us-east-1}
ECR_REPO_NAME="my-ecs-app"
CLUSTER_NAME="my-app-cluster"
LOG_GROUP_NAME="/ecs/my-ecs-app"

echo "  Configuration:"
echo "  Region: $REGION"
echo "  ECR Repository: $ECR_REPO_NAME"
echo "  ECS Cluster: $CLUSTER_NAME"
echo "  Log Group: $LOG_GROUP_NAME"
echo ""

# Check AWS CLI and credentials
echo " Checking AWS credentials..."
aws sts get-caller-identity > /dev/null || {
    echo " AWS credentials not configured. Run 'aws configure' first."
    exit 1
}

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo " AWS Account: $ACCOUNT_ID"
echo ""

# 1. Create ECR Repository
echo " Step 1: Creating ECR Repository..."
if aws ecr describe-repositories --repository-names $ECR_REPO_NAME --region $REGION >/dev/null 2>&1; then
    echo " ECR repository '$ECR_REPO_NAME' already exists"
else
    aws ecr create-repository \
        --repository-name $ECR_REPO_NAME \
        --region $REGION \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256
    echo " ECR repository '$ECR_REPO_NAME' created"
fi

ECR_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO_NAME"
echo " ECR URI: $ECR_URI"
echo ""

# 2. Create ECS Cluster
echo "  Step 2: Creating ECS Cluster..."
if aws ecs describe-clusters --clusters $CLUSTER_NAME --region $REGION --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
    echo " ECS cluster '$CLUSTER_NAME' already exists"
else
    aws ecs create-cluster \
        --cluster-name $CLUSTER_NAME \
        --capacity-providers FARGATE FARGATE_SPOT \
        --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1 \
        --region $REGION \
        --tags key=Project,value=ECS-Fargate-Demo key=Environment,value=Development
    echo " ECS cluster '$CLUSTER_NAME' created"
fi
echo ""

# 3. Create CloudWatch Log Group
echo " Step 3: Creating CloudWatch Log Group..."
if aws logs describe-log-groups --log-group-name-prefix $LOG_GROUP_NAME --region $REGION --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$LOG_GROUP_NAME"; then
    echo " Log group '$LOG_GROUP_NAME' already exists"
else
    aws logs create-log-group \
        --log-group-name $LOG_GROUP_NAME \
        --region $REGION
    
    # Set retention policy to 7 days to control costs
    aws logs put-retention-policy \
        --log-group-name $LOG_GROUP_NAME \
        --retention-in-days 7 \
        --region $REGION
    echo " Log group '$LOG_GROUP_NAME' created with 7-day retention"
fi
echo ""

# 4. Create/Verify ECS Task Execution Role
echo " Step 4: Setting up ECS Task Execution Role..."
ROLE_NAME="ecsTaskExecutionRole"

if aws iam get-role --role-name $ROLE_NAME >/dev/null 2>&1; then
    echo " IAM role '$ROLE_NAME' already exists"
else
    # Create trust policy for ECS tasks
    cat > /tmp/ecs-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ecs-tasks.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

    # Create the role
    aws iam create-role \
        --role-name $ROLE_NAME \
        --assume-role-policy-document file:///tmp/ecs-trust-policy.json

    # Attach the managed policy
    aws iam attach-role-policy \
        --role-name $ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

    echo "✅ IAM role '$ROLE_NAME' created and configured"
    rm /tmp/ecs-trust-policy.json
fi

EXECUTION_ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"
echo " Execution Role ARN: $EXECUTION_ROLE_ARN"
echo ""

# 5. Update task definition with correct values
echo " Step 5: Updating task definition template..."
if [ -f "infrastructure/task-definition.json" ]; then
    # Create backup
    cp infrastructure/task-definition.json infrastructure/task-definition.json.backup
    
    # Update placeholders with actual values
    sed -i.tmp "s|YOUR_ACCOUNT_ID|$ACCOUNT_ID|g" infrastructure/task-definition.json
    sed -i.tmp "s|us-east-1|$REGION|g" infrastructure/task-definition.json
    rm infrastructure/task-definition.json.tmp
    
    echo " Task definition updated with account-specific values"
else
    echo " Task definition not found at infrastructure/task-definition.json"
    echo "    This will be created during deployment"
fi
echo ""

# 6. Get VPC and Subnet information for deployment
echo " Step 6: Gathering VPC information..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text --region $REGION)
echo " Default VPC ID: $VPC_ID"

SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "Subnets[*].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch]" \
    --output table --region $REGION)
echo " Available Subnets:"
echo "$SUBNETS"
echo ""

# Create environment file for scripts
echo " Step 7: Creating environment configuration..."
cat > .env << EOF
# AWS Configuration
AWS_REGION=$REGION
AWS_ACCOUNT_ID=$ACCOUNT_ID

# ECS Configuration
CLUSTER_NAME=$CLUSTER_NAME
ECR_REPO_NAME=$ECR_REPO_NAME
ECR_URI=$ECR_URI
LOG_GROUP_NAME=$LOG_GROUP_NAME

# IAM
EXECUTION_ROLE_ARN=$EXECUTION_ROLE_ARN

# Networking
VPC_ID=$VPC_ID
EOF

echo " Environment configuration saved to .env"
echo ""

echo " Bootstrap Complete!"
echo "===================="
echo " ECR Repository: $ECR_URI"
echo " ECS Cluster: $CLUSTER_NAME" 
echo " CloudWatch Logs: $LOG_GROUP_NAME"
echo " IAM Role: $EXECUTION_ROLE_ARN"
echo " VPC: $VPC_ID"
echo ""
echo " Next Steps:"
echo "1. Build and deploy: ./scripts/deploy.sh"
echo "2. Test application: curl http://[ALB-DNS]/health"
echo "3. View logs: aws logs tail $LOG_GROUP_NAME --follow"
echo "4. Clean up: ./scripts/cleanup.sh"
echo ""
echo " Cost Note: These foundational resources have minimal cost"
echo "   Main costs occur during deployment (ALB + Fargate tasks)"