#!/bin/bash

# Common functions for benchmark orchestration across cloud providers
# This file provides shared functionality for all benchmark.sh scripts

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
	echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1" >&2
}

error() {
	echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

warning() {
	echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

# Get docker command for demo type
get_demo_command() {
	local worker_count=${1}
	local compose_path=${2}

	echo "docker compose --file ${compose_path} up"
}

check_tool() {
	local tool=$1
	local install_hint=${2:-"Please install $tool"}

	if ! command -v "$tool" &>/dev/null; then
		error "$tool is not installed or not in PATH. $install_hint"
		return 1
	fi
	return 0
}

validate_aws_tools() {
	log "Validating AWS tools..."

	if ! check_tool "aws" "Please install AWS CLI: https://aws.amazon.com/cli/"; then
		return 1
	fi

	success "AWS tools validated"
	return 0
}

validate_common_tools() {
	log "Validating common tools..."

	local tools=("curl" "jq")
	for tool in "${tools[@]}"; do
		if ! check_tool "$tool"; then
			return 1
		fi
	done

	success "Common tools validated"
	return 0
}

# Generic cleanup function template
# Each cloud provider should implement cleanup_instances()
generic_cleanup() {
	log "Starting cleanup process..."

	if declare -f cleanup_instances >/dev/null; then
		cleanup_instances
	else
		warning "No cleanup_instances function defined - skipping instance cleanup"
	fi

	success "Cleanup completed"
}

wait_for_http() {
	local ip=$1
	local port=$2
	local max_attempts=${3:-60}
	local retry_delay=${4:-5}

	log "Waiting for HTTP service at $ip:$port..."

	for ((i = 1; i <= max_attempts; i++)); do
		if curl -f --max-time 5 "http://$ip:$port" >/dev/null 2>&1; then
			success "Service is ready at $ip:$port"
			return 0
		fi

		if ((i % 10 == 0)); then
			log "Still waiting... attempt $i/$max_attempts"
		fi
		sleep "$retry_delay"
	done

	error "Service not ready after $((max_attempts * retry_delay)) seconds"
	return 1
}

validate_required_vars() {
	local vars=("$@")
	local missing=()

	for var in "${vars[@]}"; do
		if [[ -z "${!var}" ]]; then
			missing+=("$var")
		fi
	done

	if [[ ${#missing[@]} -gt 0 ]]; then
		error "Missing required environment variables: ${missing[*]}"
		return 1
	fi

	return 0
}
