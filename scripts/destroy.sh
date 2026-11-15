#!/bin/bash
# Removes everything Terraform created (avoid AWS charges!)
set -e
cd "$(dirname "$0")/../terraform"
terraform destroy -auto-approve
echo "All MediCart resources destroyed."
