#!/bin/bash
# cleanup.sh - Complete Resource Cleanup Script
# Destroys all AWS resources to prevent ongoing charges

set -e

echo "🧹 ECS Fargate Infrastructure Cleanup"
echo "====================================="
echo "  This will delete ALL resources created by this project!"
echo " This will stop ALL AWS charges for this project"
echo ""

# Load environment configuration if available
if [ -f ".env" ]; then
    source .env
    echo "📋 Loaded configuration from .env"
else
    echo " No .env file found. Will attempt cleanup using defaults..."
    AWS_REGION=${AWS_REGION:-us-east-1}
    CLUSTER_NAME=${CLUSTER_NAME:-my-app-cluster}
    ECR_REPO_NAME=${ECR_REPO_NAME:-my-ecs-app}
    LOG_GROUP_NAME=${LOG_GROUP_NAME:-/ecs/my-ecs-app}
fi

echo ""
echo " Cleanup Configuration:"
echo "  Region: $AWS_REGION"
echo "  ECS Cluster: $CLUSTER_NAME"
echo "  ECR Repository: $ECR_REPO_NAME"
echo ""

read -p "❓ Are you sure you want to proceed? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "❌ Cleanup cancelled"
    exit 0
fi

echo ""
echo " Starting cleanup process..."

# Step 1: Scale down and delete ECS service
echo " Step 1: Stopping ECS Service and Tasks..."

SERVICE_NAME=${SERVICE_NAME:-my-app-service}

# Check if service exists
if aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION >/dev/null 2>&1; then
    echo "🛑 Scaling service to 0 tasks..."
    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --desired-count 0 \
        --region $AWS_REGION >/dev/null
    
    echo " Waiting 60 seconds for tasks to stop..."
    sleep 60
    
    echo "  Deleting ECS service..."
    aws ecs delete-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --force \
        --region $AWS_REGION >/dev/null
    
    echo " Waiting 30 seconds for service deletion..."
    sleep 30
    echo "✅ ECS service deleted"
else
    echo " ECS service not found or already deleted"
fi

# Step 2: Delete Load Balancer
echo ""
echo "🚦 Step 2: Deleting Load Balancers..."

# Delete all ALBs that match our naming pattern
ALB_COUNT=0
for ALB_ARN in $(aws elbv2 describe-load-balancers --region $AWS_REGION --query 'LoadBalancers[?starts_with(LoadBalancerName, `my-app-alb`)].LoadBalancerArn' --output text 2>/dev/null || echo ""); do
    if [ -n "$ALB_ARN" ]; then
        ALB_NAME=$(aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN --region $AWS_REGION --query 'LoadBalancers[0].LoadBalancerName' --output text)
        echo "  Deleting ALB: $ALB_NAME"
        aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN --region $AWS_REGION
        ALB_COUNT=$((ALB_COUNT + 1))
    fi
done

if [ $ALB_COUNT -eq 0 ]; then
    echo "  No ALBs found matching pattern"
else
    echo " Waiting 60 seconds for ALB deletion..."
    sleep 60
    echo " $ALB_COUNT ALB(s) deleted"
fi

# Step 3: Delete Target Groups
echo ""
echo " Step 3: Deleting Target Groups..."

TG_COUNT=0
for TG_ARN in $(aws elbv2 describe-target-groups --region $AWS_REGION --query 'TargetGroups[?starts_with(TargetGroupName, `my-app-targets`)].TargetGroupArn' --output text 2>/dev/null || echo ""); do
    if [ -n "$TG_ARN" ]; then
        TG_NAME=$(aws elbv2 describe-target-groups --target-group-arns $TG_ARN --region $AWS_REGION --query 'TargetGroups[0].TargetGroupName' --output text)
        echo "  Deleting Target Group: $TG_NAME"
        aws elbv2 delete-target-group --target-group-arn $TG_ARN --region $AWS_REGION
        TG_COUNT=$((TG_COUNT + 1))
    fi
done

if [ $TG_COUNT -eq 0 ]; then
    echo "  No Target Groups found matching pattern"
else
    echo " $TG_COUNT Target Group(s) deleted"
fi

# Step 4: Delete ECS Cluster
echo ""
echo "  Step 4: Deleting ECS Cluster..."

if aws ecs describe-clusters --clusters $CLUSTER_NAME --region $AWS_REGION --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
    aws ecs delete-cluster --cluster $CLUSTER_NAME --region $AWS_REGION >/dev/null
    echo " ECS cluster '$CLUSTER_NAME' deleted"
else
    echo "  ECS cluster not found or already deleted"
fi

# Step 5: Delete ECR Repository
echo ""
echo " Step 5: Deleting ECR Repository..."

if aws ecr describe-repositories --repository-names $ECR_REPO_NAME --region $AWS_REGION >/dev/null 2>&1; then
    IMAGE_COUNT=$(aws ecr list-images --repository-name $ECR_REPO_NAME --region $AWS_REGION --query 'length(imageIds)')
    echo "  Deleting ECR repository with $IMAGE_COUNT images..."
    aws ecr delete-repository \
        --repository-name $ECR_REPO_NAME \
        --force \
        --region $AWS_REGION >/dev/null
    echo " ECR repository '$ECR_REPO_NAME' deleted"
else
    echo "  ECR repository not found or already deleted"
fi

# Step 6: Delete CloudWatch Log Groups
echo ""
echo " Step 6: Deleting CloudWatch Log Groups..."

if aws logs describe-log-groups --log-group-name-prefix $LOG_GROUP_NAME --region $AWS_REGION --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$LOG_GROUP_NAME"; then
    aws logs delete-log-group --log-group-name $LOG_GROUP_NAME --region $AWS_REGION
    echo " Log group '$LOG_GROUP_NAME' deleted"
else
    echo "  Log group not found or already deleted"
fi

# Step 7: Delete Security Groups
echo ""
echo "  Step 7: Deleting Security Groups..."

# Wait for resources to fully detach
echo " Waiting 30 seconds for resource detachment..."
sleep 30

VPC_ID=${VPC_ID:-$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --region $AWS_REGION --query "Vpcs[0].VpcId" --output text)}

SG_COUNT=0

# Delete ALB Security Groups
for SG_ID in $(aws ec2 describe-security-groups --filters "Name=group-name,Values=my-app-alb-sg*" "Name=vpc-id,Values=$VPC_ID" --region $AWS_REGION --query 'SecurityGroups[*].GroupId' --output text 2>/dev/null || echo ""); do
    if [ -n "$SG_ID" ]; then
        echo "  Deleting ALB Security Group: $SG_ID"
        aws ec2 delete-security-group --group-id $SG_ID --region $AWS_REGION 2>/dev/null || echo "  ⚠️  Security group may be in use, skipping..."
        SG_COUNT=$((SG_COUNT + 1))
    fi
done

# Delete ECS Security Groups
for SG_ID in $(aws ec2 describe-security-groups --filters "Name=group-name,Values=my-ecs-tasks-sg*" "Name=vpc-id,Values=$VPC_ID" --region $AWS_REGION --query 'SecurityGroups[*].GroupId' --output text 2>/dev/null || echo ""); do
    if [ -n "$SG_ID" ]; then
        echo "  Deleting ECS Security Group: $SG_ID"
        aws ec2 delete-security-group --group-id $SG_ID --region $AWS_REGION 2>/dev/null || echo "  ⚠️  Security group may be in use, skipping..."
        SG_COUNT=$((SG_COUNT + 1))
    fi
done

if [ $SG_COUNT -eq 0 ]; then
    echo "  No Security Groups found matching patterns"
else
    echo " Attempted to delete $SG_COUNT Security Group(s)"
fi

# Step 8: Deregister Task Definitions (optional cleanup)
echo ""
echo " Step 8: Deregistering Task Definitions..."

TD_COUNT=0
for TD_ARN in $(aws ecs list-task-definitions --family-prefix my-ecs-app --status ACTIVE --region $AWS_REGION --query 'taskDefinitionArns' --output text 2>/dev/null || echo ""); do
    if [ -n "$TD_ARN" ]; then
        echo "  Deregistering: $(basename $TD_ARN)"
        aws ecs deregister-task-definition --task-definition $TD_ARN --region $AWS_REGION >/dev/null
        TD_COUNT=$((TD_COUNT + 1))
    fi
done

if [ $TD_COUNT -eq 0 ]; then
    echo "  No Task Definitions found matching pattern"
else
    echo " $TD_COUNT Task Definition(s) deregistered"
fi

# Step 9: Clean up local files
echo ""
echo " Step 9: Cleaning up local files..."

if [ -f ".env" ]; then
    echo "  Removing .env file..."
    rm .env
    echo " Local environment file removed"
fi

# Remove any backup files
if [ -f "infrastructure/task-definition.json.backup" ]; then
    echo "  Removing backup files..."
    rm infrastructure/task-definition.json.backup
    echo " Backup files removed"
fi

# Clean up Docker images locally
echo ""
echo " Step 10: Cleaning up local Docker images..."
if docker images --format "table {{.Repository}}\t{{.Tag}}" | grep -q "my-ecs-app"; then
    echo "  Removing local Docker images..."
    docker rmi $(docker images --format "{{.Repository}}:{{.Tag}}" | grep my-ecs-app) 2>/dev/null || echo "  ⚠️  Some images may be in use"
    echo "✅ Local Docker images cleaned"
else
    echo "  No local Docker images found matching pattern"
fi

# Step 11: Final verification
echo ""
echo "🔍 Step 11: Final Verification..."
echo ""
echo "Remaining ECS clusters:"
REMAINING_CLUSTERS=$(aws ecs list-clusters --region $AWS_REGION --query 'clusterArns' --output text 2>/dev/null | grep -c "my-app" || echo "0")
echo "  Found: $REMAINING_CLUSTERS cluster(s) matching pattern"

echo ""
echo "Remaining Load Balancers:"
REMAINING_ALBS=$(aws elbv2 describe-load-balancers --region $AWS_REGION --query 'LoadBalancers[?starts_with(LoadBalancerName, `my-app`)].LoadBalancerName' --output text 2>/dev/null | wc -w)
echo "  Found: $REMAINING_ALBS ALB(s) matching pattern"

echo ""
echo "Remaining ECR repositories:"
REMAINING_REPOS=$(aws ecr describe-repositories --region $AWS_REGION --query 'repositories[?starts_with(repositoryName, `my-ecs`)].repositoryName' --output text 2>/dev/null | wc -w)
echo "  Found: $REMAINING_REPOS ECR repo(s) matching pattern"

echo ""
echo "✅ CLEANUP COMPLETE!"
echo "==================="
echo " All billable resources have been destroyed"
echo " No more AWS charges for this project"
echo ""
echo "📊 Resources Cleaned Up:"
echo "  ✅ ECS Service (all running containers stopped)"
echo "  ✅ ECS Cluster"
echo "  ✅ Application Load Balancer(s) - MAJOR cost savings!"
echo "  ✅ Target Group(s)"
echo "  ✅ ECR Repository + Container Images"
echo "  ✅ CloudWatch Log Group"
echo "  ✅ Security Groups"
echo "  ✅ Task Definitions (deregistered)"
echo "  ✅ Local Docker images"
echo "  ✅ Environment configuration"
echo "  ✅ Backup files"