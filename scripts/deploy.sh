#!/bin/bash
# ============================================================
#  One-command deployment (Practical 5: Automated Deployment)
#   1. Terraform provisions AWS infra
#   2. Ansible configures EC2 and deploys the Dockerised app
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${GREEN}[$(date +%H:%M:%S)] $*${NC}"; }

log "Checking prerequisites..."
for c in aws terraform ansible-playbook; do command -v $c >/dev/null || { echo "$c not installed"; exit 1; }; done
aws sts get-caller-identity --query Arn --output text || { echo "AWS credentials not configured"; exit 1; }

log "Step 1/3: Terraform - provisioning infrastructure"
cd "$ROOT/terraform"
terraform init -input=false
terraform apply -auto-approve
IP=$(terraform output -raw public_ip)

log "Step 2/3: Waiting for SSH on $IP ..."
cd "$ROOT/ansible"
chmod 600 medicart-key.pem
for i in {1..30}; do
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i medicart-key.pem ubuntu@"$IP" true 2>/dev/null && break
  echo -e "${YELLOW}  ...not ready yet ($i)${NC}"; sleep 10
done

log "Step 3/3: Ansible - configuring server and deploying app"
ansible-playbook site.yml

log "DONE! Website: http://$IP"
cd "$ROOT/terraform" && terraform output
