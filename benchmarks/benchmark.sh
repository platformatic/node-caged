#!/bin/bash

set -e

# Disable AWS CLI pager (prevents less/more from opening)
export AWS_PAGER=""

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR" && pwd)"
source "$PROJECT_ROOT/lib/common.sh"

CLUSTER_NAME="${CLUSTER_NAME:-caged-benchmark-$(date +%s)}"
AWS_PROFILE="${AWS_PROFILE}"
NODE_TYPE="${NODE_TYPE:-m5.2xlarge}"
NODE_COUNT="${NODE_COUNT:-6}"
FRAMEWORK="${FRAMEWORK:-next}"
FRAMEWORK_SOURCE_DIR="$PROJECT_ROOT/$FRAMEWORK"
KUBE_MANIFEST="${FRAMEWORK_SOURCE_DIR}/kube.yaml"
AMI_ID="${AMI_ID:-ami-07b2b18045edffe90}" # Amazon Linux 2023 arm64
LOADTESTING_INSTANCE_TYPE="${LOADTESTING_INSTANCE_TYPE:-c7gn.2xlarge}"
ECR_REPO_NAME="${ECR_REPO_NAME:-caged-benchmark}"

# Image configuration: standard Node.js vs pointer-compressed (caged)
STANDARD_BASE_IMAGE="${STANDARD_BASE_IMAGE:-node:25-bookworm-slim}"
CAGED_BASE_IMAGE="${CAGED_BASE_IMAGE:-platformatic/node-caged:slim}"

# Infrastructure resource names (set by creation functions)
CLUSTER_ROLE_NAME=""
NODE_ROLE_NAME=""
VPC_ID=""
SUBNET_IDS=""
IGW_ID=""
RTB_ID=""
CLUSTER_ROLE_ARN=""
NODE_ROLE_ARN=""
KUBE_CONTEXT=""
LOAD_TEST_INSTANCE_ID=""
SECURITY_GROUP_ID=""
AWS_ACCOUNT_ID=""
AWS_REGION=""
ECR_IMAGE_URI_STANDARD=""
ECR_IMAGE_URI_CAGED=""
ECR_REPO_CREATED=""

cleanup_instances() {
	# Terminate load test EC2 instance and wait for it
	if [[ -n "$LOAD_TEST_INSTANCE_ID" ]]; then
		log "Terminating load_test instance: $LOAD_TEST_INSTANCE_ID"
		aws ec2 terminate-instances \
			--instance-ids "$LOAD_TEST_INSTANCE_ID" \
			--profile "$AWS_PROFILE" >/dev/null 2>&1 || true

		log "Waiting for instance termination..."
		aws ec2 wait instance-terminated \
			--instance-ids "$LOAD_TEST_INSTANCE_ID" \
			--profile "$AWS_PROFILE" 2>/dev/null || true
	fi

	# Delete EKS node group
	if [[ -n "$CLUSTER_NAME" ]]; then
		local nodegroup_name="$CLUSTER_NAME-nodegroup"
		log "Checking for node group: $nodegroup_name"

		if aws eks describe-nodegroup \
			--cluster-name "$CLUSTER_NAME" \
			--nodegroup-name "$nodegroup_name" \
			--profile "$AWS_PROFILE" >/dev/null 2>&1; then

			log "Deleting node group: $nodegroup_name"
			aws eks delete-nodegroup \
				--cluster-name "$CLUSTER_NAME" \
				--nodegroup-name "$nodegroup_name" \
				--profile "$AWS_PROFILE" >/dev/null 2>&1 || true

			log "Waiting for node group deletion..."
			aws eks wait nodegroup-deleted \
				--cluster-name "$CLUSTER_NAME" \
				--nodegroup-name "$nodegroup_name" \
				--profile "$AWS_PROFILE" 2>&1 | grep -v "waiting" || true
		fi
	fi

	# Delete EKS cluster
	if [[ -n "$CLUSTER_NAME" ]]; then
		log "Checking if cluster exists: $CLUSTER_NAME"

		if aws eks describe-cluster \
			--name "$CLUSTER_NAME" \
			--profile "$AWS_PROFILE" >/dev/null 2>&1; then

			log "Deleting EKS cluster: $CLUSTER_NAME"
			aws eks delete-cluster \
				--name "$CLUSTER_NAME" \
				--profile "$AWS_PROFILE" >/dev/null 2>&1 || true

			log "Waiting for cluster deletion..."
			aws eks wait cluster-deleted \
				--name "$CLUSTER_NAME" \
				--profile "$AWS_PROFILE" 2>&1 | grep -v "waiting" || true
		fi
	fi

	# Delete Load Balancers in VPC (created by K8s LoadBalancer services)
	if [[ -n "$VPC_ID" ]]; then
		log "Deleting Load Balancers in VPC..."
		local lb_arns
		lb_arns=$(aws elbv2 describe-load-balancers \
			--profile "$AWS_PROFILE" \
			--output json 2>/dev/null | \
			jq -r ".LoadBalancers[] | select(.VpcId == \"$VPC_ID\") | .LoadBalancerArn" 2>/dev/null || true)

		if [[ -n "$lb_arns" ]]; then
			for arn in $lb_arns; do
				log "Deleting Load Balancer: $arn"
				aws elbv2 delete-load-balancer \
					--load-balancer-arn "$arn" \
					--profile "$AWS_PROFILE" 2>/dev/null || true
			done
			log "Waiting for Load Balancer ENIs to be released (60s)..."
			sleep 60
		fi
	fi

	# Delete security group (with retry)
	if [[ -n "$SECURITY_GROUP_ID" ]]; then
		log "Deleting security group: $SECURITY_GROUP_ID"
		local sg_retry=0
		while [[ $sg_retry -lt 5 ]]; do
			if aws ec2 delete-security-group \
				--group-id "$SECURITY_GROUP_ID" \
				--profile "$AWS_PROFILE" 2>/dev/null; then
				break
			fi
			sg_retry=$((sg_retry + 1))
			sleep 10
		done
	fi

	if [[ -n "$VPC_ID" ]]; then
		log "Deleting VPC resources..."

		# Delete all non-default security groups in VPC
		log "Deleting security groups..."
		local sgs
		sgs=$(aws ec2 describe-security-groups \
			--filters "Name=vpc-id,Values=$VPC_ID" \
			--profile "$AWS_PROFILE" \
			--output json 2>/dev/null | \
			jq -r '.SecurityGroups[] | select(.GroupName != "default") | .GroupId' 2>/dev/null || true)
		for sg in $sgs; do
			aws ec2 delete-security-group \
				--group-id "$sg" \
				--profile "$AWS_PROFILE" 2>/dev/null || true
		done

		# Delete Network Interfaces (orphaned ENIs from LBs/EKS)
		log "Deleting network interfaces..."
		local enis
		enis=$(aws ec2 describe-network-interfaces \
			--filters "Name=vpc-id,Values=$VPC_ID" \
			--query 'NetworkInterfaces[*].NetworkInterfaceId' \
			--output text \
			--profile "$AWS_PROFILE" 2>/dev/null || true)
		for eni in $enis; do
			aws ec2 delete-network-interface \
				--network-interface-id "$eni" \
				--profile "$AWS_PROFILE" 2>/dev/null || true
		done

		# Detach and delete internet gateway
		if [[ -n "$IGW_ID" ]]; then
			aws ec2 detach-internet-gateway \
				--internet-gateway-id "$IGW_ID" \
				--vpc-id "$VPC_ID" \
				--profile "$AWS_PROFILE" 2>/dev/null || true
			aws ec2 delete-internet-gateway \
				--internet-gateway-id "$IGW_ID" \
				--profile "$AWS_PROFILE" 2>/dev/null || true
		fi

		# Also check for any IGWs attached to VPC (in case IGW_ID wasn't set)
		local igws
		igws=$(aws ec2 describe-internet-gateways \
			--filters "Name=attachment.vpc-id,Values=$VPC_ID" \
			--query 'InternetGateways[*].InternetGatewayId' \
			--output text \
			--profile "$AWS_PROFILE" 2>/dev/null || true)
		for igw in $igws; do
			aws ec2 detach-internet-gateway \
				--internet-gateway-id "$igw" \
				--vpc-id "$VPC_ID" \
				--profile "$AWS_PROFILE" 2>/dev/null || true
			aws ec2 delete-internet-gateway \
				--internet-gateway-id "$igw" \
				--profile "$AWS_PROFILE" 2>/dev/null || true
		done

		# Delete subnets
		log "Deleting subnets..."
		local subnets
		subnets=$(aws ec2 describe-subnets \
			--filters "Name=vpc-id,Values=$VPC_ID" \
			--query 'Subnets[*].SubnetId' \
			--output text \
			--profile "$AWS_PROFILE" 2>/dev/null || true)
		for subnet in $subnets; do
			aws ec2 delete-subnet \
				--subnet-id "$subnet" \
				--profile "$AWS_PROFILE" 2>/dev/null || true
		done

		# Delete all non-main route tables
		log "Deleting route tables..."
		local rts
		rts=$(aws ec2 describe-route-tables \
			--filters "Name=vpc-id,Values=$VPC_ID" \
			--profile "$AWS_PROFILE" \
			--output json 2>/dev/null | \
			jq -r '.RouteTables[] | select(.Associations[0].Main != true) | .RouteTableId' 2>/dev/null || true)
		for rt in $rts; do
			aws ec2 delete-route-table \
				--route-table-id "$rt" \
				--profile "$AWS_PROFILE" 2>/dev/null || true
		done

		# Delete VPC with retry
		log "Deleting VPC: $VPC_ID"
		local vpc_retry=0
		while [[ $vpc_retry -lt 3 ]]; do
			if aws ec2 delete-vpc \
				--vpc-id "$VPC_ID" \
				--profile "$AWS_PROFILE" 2>/dev/null; then
				log "VPC deleted successfully"
				break
			fi
			vpc_retry=$((vpc_retry + 1))
			log "VPC deletion failed, retrying in 10s... (attempt $vpc_retry/3)"
			sleep 10
		done
	fi

	# Delete IAM roles
	if [[ -n "$NODE_ROLE_NAME" ]]; then
		log "Deleting node IAM role: $NODE_ROLE_NAME"
		aws iam detach-role-policy \
			--role-name "$NODE_ROLE_NAME" \
			--policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy \
			--profile "$AWS_PROFILE" 2>/dev/null || true
		aws iam detach-role-policy \
			--role-name "$NODE_ROLE_NAME" \
			--policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly \
			--profile "$AWS_PROFILE" 2>/dev/null || true
		aws iam detach-role-policy \
			--role-name "$NODE_ROLE_NAME" \
			--policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy \
			--profile "$AWS_PROFILE" 2>/dev/null || true
		aws iam delete-role \
			--role-name "$NODE_ROLE_NAME" \
			--profile "$AWS_PROFILE" 2>/dev/null || true
	fi

	if [[ -n "$CLUSTER_ROLE_NAME" ]]; then
		log "Deleting cluster IAM role: $CLUSTER_ROLE_NAME"
		aws iam detach-role-policy \
			--role-name "$CLUSTER_ROLE_NAME" \
			--policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy \
			--profile "$AWS_PROFILE" 2>/dev/null || true
		aws iam delete-role \
			--role-name "$CLUSTER_ROLE_NAME" \
			--profile "$AWS_PROFILE" 2>/dev/null || true
	fi

	# Delete ECR repository
	if [[ -n "$ECR_REPO_CREATED" && "$ECR_REPO_CREATED" == "true" ]]; then
		log "Deleting ECR repository: $ECR_REPO_NAME"
		aws ecr delete-repository \
			--repository-name "$ECR_REPO_NAME" \
			--force \
			--profile "$AWS_PROFILE" 2>/dev/null || true
	fi
}

trap generic_cleanup EXIT INT TERM

# OS-specific base64 encoding without line wraps
base64_encode() {
	local input="$1"
	if [[ "$OSTYPE" == "darwin"* ]]; then
		# macOS doesn't support -w flag
		printf '%s' "$input" | base64 | tr -d '\n'
	else
		# Linux (GNU coreutils)
		printf '%s' "$input" | base64 -w0
	fi
}

# Gzip compress then base64 encode (for large user data)
# AWS EC2 automatically decompresses gzip user data
gzip_base64_encode() {
	local input="$1"
	if [[ "$OSTYPE" == "darwin"* ]]; then
		printf '%s' "$input" | gzip -9 | base64 | tr -d '\n'
	else
		# Linux (GNU coreutils)
		printf '%s' "$input" | gzip -9 | base64 -w 0
	fi
}

validate_eks_tools() {
	log "Validating EKS tools..."

	if ! check_tool "kubectl" "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"; then
		return 1
	fi

	success "EKS tools validated"
	return 0
}

validate_framework_manifests() {
	log "Validating framework manifests for: $FRAMEWORK"

	if [[ ! -d "$FRAMEWORK_SOURCE_DIR" ]]; then
		error "Framework directory not found: $FRAMEWORK_SOURCE_DIR"
		error "Available frameworks: next"
		return 1
	fi

	if [[ ! -f "$KUBE_MANIFEST" ]]; then
		error "Kubernetes manifest not found: $KUBE_MANIFEST"
		error "Expected kube.yaml in $FRAMEWORK directory"
		return 1
	fi

	success "Framework manifests validated for: $FRAMEWORK"
	return 0
}

validate_docker() {
	log "Validating Docker..."

	if ! command -v docker &>/dev/null; then
		error "Docker is not installed. Please install Docker: https://docs.docker.com/get-docker/"
		return 1
	fi

	if ! docker info >/dev/null 2>&1; then
		error "Docker daemon is not running. Please start Docker."
		return 1
	fi

	success "Docker validated"
	return 0
}

setup_aws_info() {
	log "Getting AWS account info..."

	AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
		--profile "$AWS_PROFILE" \
		--query 'Account' \
		--output text)

	AWS_REGION=$(aws configure get region --profile "$AWS_PROFILE")

	if [[ -z "$AWS_ACCOUNT_ID" ]]; then
		error "Could not get AWS account ID"
		return 1
	fi

	if [[ -z "$AWS_REGION" ]]; then
		error "Could not get AWS region. Please set a default region with: aws configure"
		return 1
	fi

	ECR_IMAGE_URI_STANDARD="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:standard"
	ECR_IMAGE_URI_CAGED="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:caged"

	log "AWS Account: $AWS_ACCOUNT_ID"
	log "AWS Region: $AWS_REGION"
	log "ECR Image (standard): $ECR_IMAGE_URI_STANDARD"
	log "ECR Image (caged):    $ECR_IMAGE_URI_CAGED"

	success "AWS info retrieved"
}

ecr_login() {
	log "Logging in to ECR..."

	if ! aws ecr get-login-password \
		--profile "$AWS_PROFILE" \
		--region "$AWS_REGION" | \
	docker login \
		--username AWS \
		--password-stdin \
		"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"; then
		error "ECR login failed"
		return 1
	fi

	success "ECR login successful"
}

create_ecr_repository() {
	log "Creating ECR repository: $ECR_REPO_NAME"

	if aws ecr describe-repositories \
		--repository-names "$ECR_REPO_NAME" \
		--profile "$AWS_PROFILE" >/dev/null 2>&1; then
		log "Repository already exists"
		ECR_REPO_CREATED="true"
		return 0
	fi

	if ! aws ecr create-repository \
		--repository-name "$ECR_REPO_NAME" \
		--profile "$AWS_PROFILE" \
		--image-scanning-configuration scanOnPush=false \
		>/dev/null; then
		error "Failed to create ECR repository"
		return 1
	fi

	ECR_REPO_CREATED="true"
	success "ECR repository created"
}

build_and_push_images() {
	log "Building Docker images for linux/amd64..."
	log "Framework: $FRAMEWORK"
	log "Standard base: $STANDARD_BASE_IMAGE"
	log "Caged base:    $CAGED_BASE_IMAGE"
	log "This may take several minutes..."

	# Build standard image
	log "Building STANDARD image..."
	if ! docker build \
		--platform linux/amd64 \
		--build-arg BASE_IMAGE="$STANDARD_BASE_IMAGE" \
		--build-arg COMMIT_HASH="$(git rev-parse HEAD 2>/dev/null || echo 'unknown')" \
		--build-arg BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		-t "$ECR_IMAGE_URI_STANDARD" \
		"$FRAMEWORK_SOURCE_DIR"; then
		error "Docker build failed for standard image"
		return 1
	fi
	success "Standard image built: $ECR_IMAGE_URI_STANDARD"

	# Build caged image
	log "Building CAGED image (pointer compression)..."
	if ! docker build \
		--platform linux/amd64 \
		--build-arg BASE_IMAGE="$CAGED_BASE_IMAGE" \
		--build-arg COMMIT_HASH="$(git rev-parse HEAD 2>/dev/null || echo 'unknown')" \
		--build-arg BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		-t "$ECR_IMAGE_URI_CAGED" \
		"$FRAMEWORK_SOURCE_DIR"; then
		error "Docker build failed for caged image"
		return 1
	fi
	success "Caged image built: $ECR_IMAGE_URI_CAGED"

	# Push both images
	log "Pushing standard image to ECR..."
	if ! docker push "$ECR_IMAGE_URI_STANDARD"; then
		error "Docker push failed for standard image"
		return 1
	fi

	log "Pushing caged image to ECR..."
	if ! docker push "$ECR_IMAGE_URI_CAGED"; then
		error "Docker push failed for caged image"
		return 1
	fi

	# Verify both images exist in ECR
	log "Verifying images in ECR..."
	if ! aws ecr describe-images \
		--repository-name "$ECR_REPO_NAME" \
		--image-ids imageTag="standard" \
		--profile "$AWS_PROFILE" >/dev/null 2>&1; then
		error "Image verification failed - standard image not found in ECR"
		return 1
	fi

	if ! aws ecr describe-images \
		--repository-name "$ECR_REPO_NAME" \
		--image-ids imageTag="caged" \
		--profile "$AWS_PROFILE" >/dev/null 2>&1; then
		error "Image verification failed - caged image not found in ECR"
		return 1
	fi

	success "Both images pushed and verified"
}

create_security_group_for_load_test() {
	log "Creating security group for load_test instance..."

	local vpc_id=$(aws eks describe-cluster \
		--name "$CLUSTER_NAME" \
		--profile "$AWS_PROFILE" \
		--query 'cluster.resourcesVpcConfig.vpcId' \
		--output text)

	if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]; then
		error "Could not get VPC ID from EKS cluster"
		return 1
	fi

	log "Using VPC from EKS cluster: $vpc_id"

	local timestamp=$(date +%s)
	local sg_name="load_test-sg-$timestamp"

	SECURITY_GROUP_ID=$(aws ec2 create-security-group \
		--group-name "$sg_name" \
		--description "Temporary security group for load_test instance" \
		--vpc-id "$vpc_id" \
		--query 'GroupId' \
		--output text \
		--profile "$AWS_PROFILE")

	log "Created security group: $SECURITY_GROUP_ID"
	success "Security group configured"
}

configure_node_security_for_nodeports() {
	local node_ports=$1

	log "Configuring node security groups for NodePort access..."

	local node_sg=$(aws eks describe-cluster \
		--name "$CLUSTER_NAME" \
		--profile "$AWS_PROFILE" \
		--query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' \
		--output text)

	if [[ -z "$node_sg" || "$node_sg" == "None" ]]; then
		error "Could not get cluster security group"
		return 1
	fi

	log "Cluster security group: $node_sg"

	# Add ingress rules for each NodePort
	IFS=',' read -ra PORTS <<< "$node_ports"
	for port in "${PORTS[@]}"; do
		log "Adding ingress rule for NodePort $port..."

		AWS_PAGER="" aws ec2 authorize-security-group-ingress \
			--group-id "$node_sg" \
			--protocol tcp \
			--port "$port" \
			--source-group "$SECURITY_GROUP_ID" \
			--profile "$AWS_PROFILE" 2>/dev/null || {
			log "  (rule may already exist, continuing...)"
		}
	done

	success "Node security configured for ports: $node_ports"
}

create_vpc_stack() {
	log "Creating VPC infrastructure..."

	VPC_ID=$(aws ec2 create-vpc \
		--cidr-block 10.0.0.0/16 \
		--profile "$AWS_PROFILE" \
		--tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=eks-vpc-$CLUSTER_NAME}]" \
		--query 'Vpc.VpcId' \
		--output text)
	log "Created VPC: $VPC_ID"

	aws ec2 modify-vpc-attribute \
		--vpc-id "$VPC_ID" \
		--enable-dns-hostnames \
		--profile "$AWS_PROFILE"

	local igw_id=$(aws ec2 create-internet-gateway \
		--profile "$AWS_PROFILE" \
		--tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=eks-igw-$CLUSTER_NAME}]" \
		--query 'InternetGateway.InternetGatewayId' \
		--output text)
	log "Created Internet Gateway: $igw_id"

	aws ec2 attach-internet-gateway \
		--vpc-id "$VPC_ID" \
		--internet-gateway-id "$igw_id" \
		--profile "$AWS_PROFILE"

	local azs=($(aws ec2 describe-availability-zones \
		--profile "$AWS_PROFILE" \
		--query 'AvailabilityZones[0:2].ZoneName' \
		--output text))

	local subnet1=$(aws ec2 create-subnet \
		--vpc-id "$VPC_ID" \
		--cidr-block 10.0.1.0/24 \
		--availability-zone "${azs[0]}" \
		--profile "$AWS_PROFILE" \
		--tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=eks-public-subnet-1}]" \
		--query 'Subnet.SubnetId' \
		--output text)

	local subnet2=$(aws ec2 create-subnet \
		--vpc-id "$VPC_ID" \
		--cidr-block 10.0.2.0/24 \
		--availability-zone "${azs[1]}" \
		--profile "$AWS_PROFILE" \
		--tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=eks-public-subnet-2}]" \
		--query 'Subnet.SubnetId' \
		--output text)

	log "Created subnets: $subnet1, $subnet2"

	aws ec2 modify-subnet-attribute \
		--subnet-id "$subnet1" \
		--map-public-ip-on-launch \
		--profile "$AWS_PROFILE"

	aws ec2 modify-subnet-attribute \
		--subnet-id "$subnet2" \
		--map-public-ip-on-launch \
		--profile "$AWS_PROFILE"

	local rtb_id=$(aws ec2 create-route-table \
		--vpc-id "$VPC_ID" \
		--profile "$AWS_PROFILE" \
		--tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=eks-public-rtb}]" \
		--query 'RouteTable.RouteTableId' \
		--output text)
	log "Created route table: $rtb_id"

	aws ec2 create-route \
		--route-table-id "$rtb_id" \
		--destination-cidr-block 0.0.0.0/0 \
		--gateway-id "$igw_id" \
		--profile "$AWS_PROFILE" >/dev/null

	aws ec2 associate-route-table \
		--route-table-id "$rtb_id" \
		--subnet-id "$subnet1" \
		--profile "$AWS_PROFILE" >/dev/null

	aws ec2 associate-route-table \
		--route-table-id "$rtb_id" \
		--subnet-id "$subnet2" \
		--profile "$AWS_PROFILE" >/dev/null

	SUBNET_IDS="$subnet1,$subnet2"
	IGW_ID="$igw_id"
	RTB_ID="$rtb_id"

	log "VPC ID: $VPC_ID"
	log "Subnet IDs: $SUBNET_IDS"
	success "VPC infrastructure created"
}

create_cluster_iam_role() {
	local role_name="eks-cluster-role-$CLUSTER_NAME"
	CLUSTER_ROLE_NAME="$role_name"

	log "Creating EKS cluster IAM role: $role_name"

	cat >/tmp/cluster-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

	aws iam create-role \
		--role-name "$role_name" \
		--assume-role-policy-document file:///tmp/cluster-trust-policy.json \
		--profile "$AWS_PROFILE" \
		>/dev/null

	aws iam attach-role-policy \
		--policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy \
		--role-name "$role_name" \
		--profile "$AWS_PROFILE"

	CLUSTER_ROLE_ARN=$(aws iam get-role \
		--role-name "$role_name" \
		--profile "$AWS_PROFILE" \
		--query 'Role.Arn' \
		--output text)

	log "Cluster role ARN: $CLUSTER_ROLE_ARN"
	success "Cluster IAM role created"
}

create_node_iam_role() {
	local role_name="eks-node-role-$CLUSTER_NAME"
	NODE_ROLE_NAME="$role_name"

	log "Creating EKS node IAM role: $role_name"

	cat >/tmp/node-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      }
    }
  ]
}
EOF

	aws iam create-role \
		--role-name "$role_name" \
		--assume-role-policy-document file:///tmp/node-trust-policy.json \
		--profile "$AWS_PROFILE" \
		>/dev/null

	aws iam attach-role-policy \
		--policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy \
		--role-name "$role_name" \
		--profile "$AWS_PROFILE"

	aws iam attach-role-policy \
		--policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly \
		--role-name "$role_name" \
		--profile "$AWS_PROFILE"

	aws iam attach-role-policy \
		--policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy \
		--role-name "$role_name" \
		--profile "$AWS_PROFILE"

	NODE_ROLE_ARN=$(aws iam get-role \
		--role-name "$role_name" \
		--profile "$AWS_PROFILE" \
		--query 'Role.Arn' \
		--output text)

	log "Node role ARN: $NODE_ROLE_ARN"
	success "Node IAM role created"
}

create_eks_cluster() {
	log "Creating EKS cluster: $CLUSTER_NAME"
	log "This may take 15-20 minutes..."

	aws eks create-cluster \
		--name "$CLUSTER_NAME" \
		--role-arn "$CLUSTER_ROLE_ARN" \
		--resources-vpc-config subnetIds="$SUBNET_IDS" \
		--profile "$AWS_PROFILE" \
		>/dev/null

	log "Waiting for cluster to be ACTIVE..."
	local max_attempts=60
	local retry_delay=15

	for ((i = 1; i <= max_attempts; i++)); do
		local status=$(aws eks describe-cluster \
			--name "$CLUSTER_NAME" \
			--profile "$AWS_PROFILE" \
			--query 'cluster.status' \
			--output text)

		if [[ "$status" == "ACTIVE" ]]; then
			success "EKS cluster is ACTIVE"
			return 0
		fi

		if ((i % 4 == 0)); then
			log "Cluster status: $status (attempt $i/$max_attempts)"
		fi
		sleep "$retry_delay"
	done

	error "Cluster not ACTIVE after $((max_attempts * retry_delay)) seconds"
	return 1
}

create_nodegroup() {
	local nodegroup_name="$CLUSTER_NAME-nodegroup"

	log "Creating managed node group: $nodegroup_name"

	aws eks create-nodegroup \
		--cluster-name "$CLUSTER_NAME" \
		--nodegroup-name "$nodegroup_name" \
		--node-role "$NODE_ROLE_ARN" \
		--subnets $(echo "$SUBNET_IDS" | tr ',' ' ') \
		--instance-types "$NODE_TYPE" \
		--scaling-config minSize="$NODE_COUNT",maxSize="$NODE_COUNT",desiredSize="$NODE_COUNT" \
		--profile "$AWS_PROFILE" \
		>/dev/null

	log "Waiting for node group to be ACTIVE..."
	local max_attempts=60
	local retry_delay=10

	for ((i = 1; i <= max_attempts; i++)); do
		local status=$(aws eks describe-nodegroup \
			--cluster-name "$CLUSTER_NAME" \
			--nodegroup-name "$nodegroup_name" \
			--profile "$AWS_PROFILE" \
			--query 'nodegroup.status' \
			--output text 2>/dev/null || echo "CREATING")

		if [[ "$status" == "ACTIVE" ]]; then
			success "Node group is ACTIVE"
			return 0
		fi

		if ((i % 6 == 0)); then
			log "Node group status: $status (attempt $i/$max_attempts)"
		fi
		sleep "$retry_delay"
	done

	error "Node group not ACTIVE after $((max_attempts * retry_delay)) seconds"
	return 1
}

wait_for_nodes() {
	log "Waiting for nodes to be ready..."

	local max_attempts=60
	local retry_delay=5

	for ((i = 1; i <= max_attempts; i++)); do
		local ready_nodes=$(kubectl --context "$KUBE_CONTEXT" get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo "0")

		if [[ "$ready_nodes" -ge "$NODE_COUNT" ]]; then
			success "All $NODE_COUNT nodes are ready"
			return 0
		fi

		if ((i % 10 == 0)); then
			log "Still waiting for nodes... $ready_nodes/$NODE_COUNT ready (attempt $i/$max_attempts)"
		fi
		sleep "$retry_delay"
	done

	error "Nodes not ready after $((max_attempts * retry_delay)) seconds"
	return 1
}

apply_framework_manifests() {
	log "Applying $FRAMEWORK manifests from $KUBE_MANIFEST..."

	# Template the manifest with both ECR image URIs
	sed "s|IMAGE_PLACEHOLDER_STANDARD|${ECR_IMAGE_URI_STANDARD}|g; s|IMAGE_PLACEHOLDER_CAGED|${ECR_IMAGE_URI_CAGED}|g" "$KUBE_MANIFEST" | \
		kubectl --context "$KUBE_CONTEXT" apply -f -

	success "$FRAMEWORK manifests applied"
}

wait_for_pods() {
	log "Waiting for pods to be ready..."

	local max_attempts=120
	local retry_delay=5

	for ((i = 1; i <= max_attempts; i++)); do
		local pods=$(kubectl --context "$KUBE_CONTEXT" get pods --all-namespaces --no-headers 2>/dev/null | grep -v "kube-system" || echo "")

		if [[ -z "$pods" ]]; then
			if ((i % 10 == 0)); then
				log "No pods found yet... (attempt $i/$max_attempts)"
			fi
			sleep "$retry_delay"
			continue
		fi

		# Check if all pods are ready (status shows "Running" and ready count matches total count)
		local not_ready=$(echo "$pods" | awk '{
			# Extract ready count (e.g., "1/1" -> both should match)
			split($3, ready, "/");
			if (ready[1] != ready[2] || $4 != "Running") {
				print $0
			}
		}')

		if [[ -z "$not_ready" ]]; then
			success "All pods are ready"
			kubectl --context "$KUBE_CONTEXT" get pods --all-namespaces | grep -v "kube-system"
			return 0
		fi

		if ((i % 10 == 0)); then
			log "Still waiting for pods to be ready... (attempt $i/$max_attempts)"
			kubectl --context "$KUBE_CONTEXT" get pods --all-namespaces | grep -v "kube-system" || true
		fi
		sleep "$retry_delay"
	done

	error "Pods not ready after $((max_attempts * retry_delay)) seconds"
	kubectl --context "$KUBE_CONTEXT" get pods --all-namespaces
	return 1
}

# ============================================================================
# DIAGNOSTIC FUNCTIONS
# ============================================================================

show_cluster_info() {
	log "============================================================"
	log "CLUSTER INFORMATION"
	log "============================================================"

	log "Cluster: $CLUSTER_NAME"
	log "Region: $AWS_REGION"
	log "Node Type: $NODE_TYPE"
	log "Node Count: $NODE_COUNT"

	log ""
	log "--- Kubernetes Version ---"
	kubectl --context "$KUBE_CONTEXT" version --short 2>/dev/null || kubectl --context "$KUBE_CONTEXT" version

	log ""
	log "--- Node Information ---"
	kubectl --context "$KUBE_CONTEXT" get nodes -o wide

	log ""
	log "--- Node Resources ---"
	kubectl --context "$KUBE_CONTEXT" describe nodes | grep -A 10 "Allocated resources:" || true

	log "============================================================"
}

show_deployment_details() {
	log "============================================================"
	log "DEPLOYMENT DETAILS"
	log "============================================================"

	log ""
	log "--- Deployments ---"
	kubectl --context "$KUBE_CONTEXT" get deployments -o wide

	log ""
	log "--- Pods (detailed) ---"
	kubectl --context "$KUBE_CONTEXT" get pods -o wide

	log ""
	log "--- Pod Resource Requests/Limits ---"
	kubectl --context "$KUBE_CONTEXT" get pods -o custom-columns=\
'NAME:.metadata.name,'\
'CPU_REQ:.spec.containers[0].resources.requests.cpu,'\
'CPU_LIM:.spec.containers[0].resources.limits.cpu,'\
'MEM_REQ:.spec.containers[0].resources.requests.memory,'\
'MEM_LIM:.spec.containers[0].resources.limits.memory,'\
'NODE:.spec.nodeName'

	log ""
	log "--- Services ---"
	kubectl --context "$KUBE_CONTEXT" get services -o wide

	log ""
	log "--- Pod Distribution by Node ---"
	kubectl --context "$KUBE_CONTEXT" get pods -o wide --no-headers | awk '{nodes[$7]++} END {for (n in nodes) print n ": " nodes[n] " pods"}'

	log "============================================================"
}

show_pod_events() {
	log "============================================================"
	log "POD EVENTS (last 50)"
	log "============================================================"
	kubectl --context "$KUBE_CONTEXT" get events --sort-by='.lastTimestamp' | tail -50
	log "============================================================"
}

health_check_endpoints() {
	local url_node_standard=$1
	local url_node_caged=$2
	local url_watt_standard=$3
	local url_watt_caged=$4

	log "============================================================"
	log "ENDPOINT HEALTH CHECKS"
	log "============================================================"

	for endpoint in "Node-Standard:$url_node_standard" "Node-Caged:$url_node_caged" "Watt-Standard:$url_watt_standard" "Watt-Caged:$url_watt_caged"; do
		local name="${endpoint%%:*}"
		local url="${endpoint#*:}"

		log ""
		log "--- $name ($url) ---"

		# Try multiple times with curl
		local success_count=0
		local total_time=0

		for i in {1..5}; do
			local result=$(curl -s -o /dev/null -w "%{http_code},%{time_total}" --connect-timeout 5 --max-time 10 "$url/" 2>/dev/null || echo "000,0")
			local http_code="${result%%,*}"
			local time_sec="${result##*,}"

			if [[ "$http_code" == "200" ]]; then
				success_count=$((success_count + 1))
				total_time=$(echo "$total_time + $time_sec" | bc)
				log "  Request $i: HTTP $http_code (${time_sec}s)"
			else
				log "  Request $i: HTTP $http_code (FAILED)"
			fi
			sleep 0.5
		done

		if [[ $success_count -gt 0 ]]; then
			local avg_time=$(echo "scale=3; $total_time / $success_count" | bc)
			success "$name: $success_count/5 successful, avg response time: ${avg_time}s"
		else
			error "$name: All health checks failed!"
		fi
	done

	log "============================================================"
}

collect_pod_logs() {
	local deployment=$1
	local lines=${2:-100}

	log "============================================================"
	log "POD LOGS: $deployment (last $lines lines per pod)"
	log "============================================================"

	local pods=$(kubectl --context "$KUBE_CONTEXT" get pods -l "app.kubernetes.io/instance=$deployment" -o jsonpath='{.items[*].metadata.name}')

	for pod in $pods; do
		log ""
		log "--- Pod: $pod ---"
		kubectl --context "$KUBE_CONTEXT" logs "$pod" --tail="$lines" 2>/dev/null || log "(no logs available)"
	done

	log "============================================================"
}

collect_all_pod_logs() {
	log ""
	log "########################################################################"
	log "COLLECTING POD LOGS FROM ALL DEPLOYMENTS"
	log "########################################################################"

	collect_pod_logs "${FRAMEWORK}-node-standard" 50
	collect_pod_logs "${FRAMEWORK}-node-caged" 50
	collect_pod_logs "${FRAMEWORK}-watt-standard" 50
	collect_pod_logs "${FRAMEWORK}-watt-caged" 50
}

show_resource_usage() {
	log "============================================================"
	log "RESOURCE USAGE (kubectl top)"
	log "============================================================"

	log ""
	log "--- Node Resource Usage ---"
	kubectl --context "$KUBE_CONTEXT" top nodes 2>/dev/null || log "(metrics-server not available)"

	log ""
	log "--- Pod Resource Usage ---"
	kubectl --context "$KUBE_CONTEXT" top pods 2>/dev/null || log "(metrics-server not available)"

	log "============================================================"
}

show_pod_descriptions() {
	local deployment=$1

	log "============================================================"
	log "POD DESCRIPTIONS: $deployment"
	log "============================================================"

	local pods=$(kubectl --context "$KUBE_CONTEXT" get pods -l "app.kubernetes.io/instance=$deployment" -o jsonpath='{.items[*].metadata.name}')

	for pod in $pods; do
		log ""
		log "--- Pod: $pod ---"
		kubectl --context "$KUBE_CONTEXT" describe pod "$pod" | grep -A 20 "Conditions:" || true
		kubectl --context "$KUBE_CONTEXT" describe pod "$pod" | grep -A 5 "Events:" || true
	done

	log "============================================================"
}

pre_benchmark_diagnostics() {
	log ""
	log "########################################################################"
	log "PRE-BENCHMARK DIAGNOSTICS"
	log "########################################################################"

	show_cluster_info
	show_deployment_details
	show_resource_usage
	show_pod_events
}

post_benchmark_diagnostics() {
	log ""
	log "########################################################################"
	log "POST-BENCHMARK DIAGNOSTICS"
	log "########################################################################"

	show_resource_usage
	show_pod_events
	collect_all_pod_logs

	log ""
	log "--- Checking for OOMKilled or CrashLoopBackOff pods ---"
	kubectl --context "$KUBE_CONTEXT" get pods -o wide | grep -E "OOMKilled|CrashLoopBackOff|Error" || log "No problematic pods found"

	log ""
	log "--- Pod restart counts ---"
	kubectl --context "$KUBE_CONTEXT" get pods -o custom-columns='NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount'
}

find_annotated_loadbalancer_services() {
	log "Finding annotated LoadBalancer services..."

	# Find all services with the benchmark annotation
	local services=$(kubectl --context "$KUBE_CONTEXT" get services -o json | jq -r '.items[] |
		select(.metadata.annotations["benchmark.platformatic.dev/expose"] == "true") |
		select(.spec.type == "LoadBalancer") |
		.metadata.name')

	if [[ -z "$services" ]]; then
		error "No LoadBalancer services found with annotation benchmark.platformatic.dev/expose=true"
		log "Available services:"
		kubectl --context "$KUBE_CONTEXT" get services
		return 1
	fi

	log "Found annotated services:"
	echo "$services" | while read -r svc; do
		log "  - $svc"
	done

	echo "$services"
}

wait_for_loadbalancer_hostnames() {
	local services=$1
	local max_attempts=60
	local retry_delay=10

	log "Waiting for LoadBalancer hostnames to be assigned..."

	for svc in $services; do
		log "Waiting for LoadBalancer hostname for service: $svc"
		local attempt=0
		local hostname=""

		while [[ $attempt -lt $max_attempts ]]; do
			hostname=$(kubectl --context "$KUBE_CONTEXT" get service "$svc" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

			if [[ -n "$hostname" && "$hostname" != "null" ]]; then
				success "Service $svc has LoadBalancer hostname: $hostname"
				break
			fi

			attempt=$((attempt + 1))
			log "Attempt $attempt/$max_attempts: LoadBalancer not ready yet for $svc..."
			sleep "$retry_delay"
		done

		if [[ -z "$hostname" || "$hostname" == "null" ]]; then
			error "LoadBalancer hostname not assigned for $svc after $((max_attempts * retry_delay)) seconds"
			kubectl --context "$KUBE_CONTEXT" get service "$svc" -o yaml
			return 1
		fi
	done

	success "All LoadBalancer hostnames assigned"
}

get_loadbalancer_url() {
	local service_name=$1
	local hostname=$(kubectl --context "$KUBE_CONTEXT" get service "$service_name" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
	echo "http://$hostname"
}

get_node_private_ip() {
	log "Getting private IP of a cluster node..."

	local node_ip=$(kubectl --context "$KUBE_CONTEXT" get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

	if [[ -z "$node_ip" ]]; then
		error "Could not get node private IP"
		kubectl --context "$KUBE_CONTEXT" get nodes -o wide
		return 1
	fi

	log "Node private IP: $node_ip"
	echo "$node_ip"
}

get_node_ports_list() {
	local services=$1
	echo "$services" | while read -r svc; do
		echo "$svc" | cut -d: -f2
	done | tr '\n' ',' | sed 's/,$//'
}

get_instance_ip() {
	aws ec2 describe-instances \
		--instance-ids "$1" \
		--query 'Reservations[0].Instances[0].PublicIpAddress' \
		--profile "$AWS_PROFILE" \
		--output text
}

launch_load_test_instance() {
	local url_node_standard=$1
	local url_node_caged=$2
	local url_watt_standard=$3
	local url_watt_caged=$4

	log "Launching load_test EC2 instance..."

	# Get a private subnet from the EKS cluster VPC (load_test needs to reach LoadBalancer endpoints)
	local vpc_id=$(aws eks describe-cluster \
		--name "$CLUSTER_NAME" \
		--profile "$AWS_PROFILE" \
		--query 'cluster.resourcesVpcConfig.vpcId' \
		--output text)

	# Use private subnet since LoadBalancers are internal
	local subnet_id=$(aws ec2 describe-subnets \
		--filters "Name=vpc-id,Values=$vpc_id" \
		--profile "$AWS_PROFILE" \
		--query 'Subnets[0].SubnetId' \
		--output text)

	if [[ -z "$subnet_id" || "$subnet_id" == "None" ]]; then
		error "Could not find subnet in VPC"
		return 1
	fi

	log "Using subnet: $subnet_id"

	local load_test_script
	load_test_script=$(cat "$FRAMEWORK_SOURCE_DIR/loadtest.sh")

	# Create user data script for load_test instance
	IFS='' read -r -d '' ac_user_script <<EOF || true
#!/bin/bash
set -x

yum update -y
yum install -y httpd-tools

# Install k6 from static binary for ARM64 support
K6_VERSION=\$(curl -s https://api.github.com/repos/grafana/k6/releases/latest | grep -oP '"tag_name": "v\K[^"]+')
curl -L "https://github.com/grafana/k6/releases/download/v\${K6_VERSION}/k6-v\${K6_VERSION}-linux-arm64.tar.gz" -o /tmp/k6.tar.gz
tar -xzf /tmp/k6.tar.gz -C /tmp
mv "/tmp/k6-v\${K6_VERSION}-linux-arm64/k6" /usr/local/bin/k6
chmod +x /usr/local/bin/k6
rm -rf /tmp/k6*

sysctl net.core.rmem_default=268435456
sysctl net.core.wmem_default=268435456
sysctl net.core.rmem_max=268435456
sysctl net.core.wmem_max=268435456
sysctl net.core.netdev_max_backlog=100000
sysctl "net.ipv4.tcp_rmem=4096 16384 134217728"
sysctl "net.ipv4.tcp_wmem=4096 16384 134217728"
sysctl "net.ipv4.tcp_mem=786432 1048576 268435456"
sysctl net.ipv4.tcp_max_tw_buckets=360000
sysctl net.ipv4.tcp_max_syn_backlog=10000
sysctl vm.min_free_kbytes=65536
sysctl vm.swappiness=0
sysctl net.core.somaxconn=10000
sysctl fs.file-max=65536

# Port exhaustion - you're likely hitting this
sysctl net.ipv4.ip_local_port_range="1024 65535"  # Current default is probably 32768-60999

# TIME_WAIT socket reuse (essential for load testing)
sysctl net.ipv4.tcp_tw_reuse=1

# Reduce TIME_WAIT duration from 60s to 30s
sysctl net.netfilter.nf_conntrack_tcp_timeout_time_wait=30  # If using conntrack

ulimit -n 1000000
sysctl fs.file-max=2097152  # System-wide
sysctl fs.nr_open=2097152

echo 'Starting benchmark via LoadBalancers'
export URL_NODE_STANDARD="$url_node_standard"
export URL_NODE_CAGED="$url_node_caged"
export URL_WATT_STANDARD="$url_watt_standard"
export URL_WATT_CAGED="$url_watt_caged"

# Create log file for benchmark results
BENCHMARK_LOG="/var/log/benchmark-results.log"
touch "\$BENCHMARK_LOG"
chmod 644 "\$BENCHMARK_LOG"

# Run load test and capture output to both console and log file
{
$load_test_script
} 2>&1 | tee -a "\$BENCHMARK_LOG"

echo 'Benchmark completed - instance will terminate'
echo "Results saved to: \$BENCHMARK_LOG"
EOF

	local ac_user_data=$(gzip_base64_encode "$ac_user_script")

	LOAD_TEST_INSTANCE_ID=$(aws ec2 run-instances \
		--image-id "$AMI_ID" \
		--count 1 \
		--instance-type "$LOADTESTING_INSTANCE_TYPE" \
		--user-data "${ac_user_data}" \
		--subnet-id "$subnet_id" \
		--security-group-ids "$SECURITY_GROUP_ID" \
		--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=benchmark-load_test}]" \
		--query 'Instances[0].InstanceId' \
		--output text \
		--profile "$AWS_PROFILE")

	success "load_test instance launched: $LOAD_TEST_INSTANCE_ID"
}

parse_console_output() {
	local temp_file=$(mktemp)
	cat >"$temp_file"

	local start_line=$(grep -n "Starting benchmark" "$temp_file" |
		grep -v '+ echo' |
		tail -1 |
		cut -d: -f1)

	# If start_line is empty, output the whole file (filtered)
	if [[ -z "$start_line" ]]; then
		sed -E 's/^\[[^]]+\] cloud-init\[[0-9]+\]: //' "$temp_file" |
			grep -v '^+ ' |
			grep -Ev 'docker run|entered blocking|entered disabled|entered promiscuous|left promiscuous|renamed from|link becomes ready|entered forwarding'
		rm -f "$temp_file"
		return
	fi

	local end_line=$(tail -n +"$start_line" "$temp_file" |
		grep -n "Benchmark completed" |
		grep -v '+ echo' |
		head -1 |
		cut -d: -f1)

	# If end_line is empty, output from start_line to end of file
	if [[ -z "$end_line" ]]; then
		sed -n "${start_line},\$p" "$temp_file" |
			sed -E 's/^\[[^]]+\] cloud-init\[[0-9]+\]: //' |
			grep -v '^+ ' |
			grep -Ev 'docker run|entered blocking|entered disabled|entered promiscuous|left promiscuous|renamed from|link becomes ready|entered forwarding'
		rm -f "$temp_file"
		return
	fi

	end_line=$((start_line + end_line - 1))

	sed -n "${start_line},${end_line}p" "$temp_file" |
		sed -E 's/^\[[^]]+\] cloud-init\[[0-9]+\]: //' |
		grep -v '^+ ' |
		grep -Ev 'docker run|entered blocking|entered disabled|entered promiscuous|left promiscuous|renamed from|link becomes ready|entered forwarding'

	rm -f "$temp_file"
}

monitor_load_test() {
	local instance_id=$1
	local previous_output=""
	local current_output=""
	local all_output=""
	local max_wait_seconds=5400  # 1.5 hours max wait (4 tests + cooldowns)
	local elapsed=0
	local check_interval=10

	# Create log file with timestamp
	local log_timestamp=$(date +%Y%m%d_%H%M%S)
	local log_file="${PROJECT_ROOT}/benchmark_${log_timestamp}.log"

	log "Monitoring load_test instance console output..."
	log "Waiting for benchmark to complete (timeout: ${max_wait_seconds}s)..."
	log "Saving logs to: $log_file"

	# Initialize log file with header
	{
		echo "========================================================================"
		echo "BENCHMARK LOG: Standard Node.js vs node-caged (pointer compression)"
		echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
		echo "Instance: $instance_id"
		echo "Cluster: $CLUSTER_NAME"
		echo "Framework: $FRAMEWORK"
		echo "Standard base: $STANDARD_BASE_IMAGE"
		echo "Caged base:    $CAGED_BASE_IMAGE"
		echo "========================================================================"
		echo ""
	} > "$log_file"

	while [[ $elapsed -lt $max_wait_seconds ]]; do
		# Check instance state first
		local instance_state=$(aws ec2 describe-instances \
			--instance-ids "$instance_id" \
			--query 'Reservations[0].Instances[0].State.Name' \
			--output text \
			--profile "$AWS_PROFILE" 2>/dev/null || echo "unknown")

		if [[ "$instance_state" == "terminated" || "$instance_state" == "shutting-down" ]]; then
			error "Load test instance terminated unexpectedly!"
			log "Instance state: $instance_state"
			echo "$all_output" >> "$log_file"
			log ""
			log "=== FULL CONSOLE OUTPUT ==="
			echo "$all_output"
			log "=== END CONSOLE OUTPUT ==="
			log "Full log saved to: $log_file"
			return 1
		fi

		current_output=$(aws ec2 get-console-output \
			--instance-id "$instance_id" \
			--query 'Output' \
			--output text \
			--latest \
			--profile "$AWS_PROFILE" 2>/dev/null || echo "")

		if [[ -n "$current_output" && "$current_output" != "$previous_output" ]]; then
			previous_output="$current_output"
			all_output="$current_output"
			# Save to log file (overwrite with latest full output)
			{
				echo "========================================================================"
				echo "BENCHMARK LOG: Standard Node.js vs node-caged (pointer compression)"
				echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
				echo "Instance: $instance_id"
				echo "Cluster: $CLUSTER_NAME"
				echo "Framework: $FRAMEWORK"
				echo "Last updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
				echo "========================================================================"
				echo ""
				echo "$current_output"
			} > "$log_file"
		fi

		# Check for successful completion
		if echo "$current_output" | grep -q "Benchmark completed"; then
			echo "$all_output" | parse_console_output

			# Save results to local file
			local results_dir="$PROJECT_ROOT/results"
			mkdir -p "$results_dir"
			local timestamp=$(date +%Y%m%d-%H%M%S)
			local results_file="$results_dir/${FRAMEWORK}-caged-${timestamp}.log"
			echo "$all_output" | parse_console_output > "$results_file"
			success "Benchmark results saved to: $results_file"
			log "Full log saved to: $log_file"

			success "Benchmark execution completed!"
			return 0
		fi

		# Check for common failure patterns
		if echo "$current_output" | grep -qiE "fatal error|panic|segmentation fault|out of memory|killed|failed to start"; then
			error "Load test script failed!"
			log ""
			log "=== FULL CONSOLE OUTPUT ==="
			echo "$all_output"
			log "=== END CONSOLE OUTPUT ==="
			log "Full log saved to: $log_file"
			return 1
		fi

		# Check for cloud-init failures
		if echo "$current_output" | grep -qE "Cloud-init.*finished.*result: fail|CRITICAL.*cloud-init"; then
			error "Cloud-init failed to run user-data script!"
			log ""
			log "=== FULL CONSOLE OUTPUT ==="
			echo "$all_output"
			log "=== END CONSOLE OUTPUT ==="
			log "Full log saved to: $log_file"
			return 1
		fi

		elapsed=$((elapsed + check_interval))
		sleep $check_interval
	done

	# Timeout reached
	error "Load test timed out after ${max_wait_seconds} seconds!"
	log ""
	log "=== FULL CONSOLE OUTPUT ==="
	echo "$all_output"
	log "=== END CONSOLE OUTPUT ==="
	log "Full log saved to: $log_file"
	return 1
}

main() {
	log "########################################################################"
	log "CAGED BENCHMARK: Standard Node.js vs Pointer Compression"
	log "Framework: $FRAMEWORK"
	log "Standard base: $STANDARD_BASE_IMAGE"
	log "Caged base:    $CAGED_BASE_IMAGE"
	log "Test matrix: Node + Watt x Standard + Caged (4 combinations)"
	log "Started at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	log "########################################################################"

	if ! validate_aws_tools || ! validate_common_tools || ! validate_eks_tools || ! validate_docker; then
		error "Tool validation failed"
		exit 1
	fi

	if ! validate_required_vars "AWS_PROFILE"; then
		exit 1
	fi

	if ! validate_framework_manifests; then
		exit 1
	fi

	# Setup AWS info and ECR
	if ! setup_aws_info; then
		exit 1
	fi

	ecr_login
	create_ecr_repository
	build_and_push_images

	# Create infrastructure
	create_vpc_stack
	create_cluster_iam_role
	create_node_iam_role
	create_eks_cluster

	KUBE_CONTEXT="$CLUSTER_NAME"
	log "Updating kubeconfig with context: $KUBE_CONTEXT"
	aws eks update-kubeconfig \
		--name "$CLUSTER_NAME" \
		--profile "$AWS_PROFILE" \
		--alias "$KUBE_CONTEXT"

	create_nodegroup
	wait_for_nodes

	apply_framework_manifests
	wait_for_pods

	local services=$(find_annotated_loadbalancer_services)

	if [[ -z "$services" ]]; then
		error "Could not find annotated LoadBalancer services"
		exit 1
	fi

	wait_for_loadbalancer_hostnames "$services"

	# Get LoadBalancer URLs for each service variant
	local url_node_standard=$(get_loadbalancer_url "${FRAMEWORK}-node-standard")
	local url_node_caged=$(get_loadbalancer_url "${FRAMEWORK}-node-caged")
	local url_watt_standard=$(get_loadbalancer_url "${FRAMEWORK}-watt-standard")
	local url_watt_caged=$(get_loadbalancer_url "${FRAMEWORK}-watt-caged")

	log "LoadBalancer URLs:"
	log "  Node Standard: $url_node_standard"
	log "  Node Caged:    $url_node_caged"
	log "  Watt Standard: $url_watt_standard"
	log "  Watt Caged:    $url_watt_caged"

	# Run pre-benchmark diagnostics
	pre_benchmark_diagnostics

	# Health check all endpoints before load testing
	health_check_endpoints "$url_node_standard" "$url_node_caged" "$url_watt_standard" "$url_watt_caged"

	create_security_group_for_load_test

	log ""
	log "########################################################################"
	log "STARTING LOAD TEST"
	log "Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	log "########################################################################"

	launch_load_test_instance "$url_node_standard" "$url_node_caged" "$url_watt_standard" "$url_watt_caged"

	log "Waiting for load_test instance to be running..."
	aws ec2 wait instance-running \
		--instance-ids "$LOAD_TEST_INSTANCE_ID" \
		--profile "$AWS_PROFILE"

	if ! monitor_load_test "$LOAD_TEST_INSTANCE_ID"; then
		error "Load test failed! Running post-benchmark diagnostics..."
		post_benchmark_diagnostics
		exit 1
	fi

	# Run post-benchmark diagnostics
	post_benchmark_diagnostics

	log ""
	log "########################################################################"
	log "BENCHMARK COMPLETED"
	log "Finished at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	log "########################################################################"

	success "Benchmark orchestration completed!"
}

main "$@"
