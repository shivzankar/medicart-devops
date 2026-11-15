#!/bin/bash
# Installs AWS CLI v2, Terraform and Ansible inside WSL Ubuntu.
set -e
sudo apt-get update -y
sudo apt-get install -y unzip curl gnupg software-properties-common python3-pip jq
# AWS CLI v2
if ! command -v aws >/dev/null; then
  curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q -o /tmp/awscliv2.zip -d /tmp && sudo /tmp/aws/install
fi
# Terraform
if ! command -v terraform >/dev/null; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update -y && sudo apt-get install -y terraform
fi
# Ansible
if ! command -v ansible >/dev/null; then
  sudo add-apt-repository -y --update ppa:ansible/ansible
  sudo apt-get install -y ansible
fi

echo "-----"; aws --version; terraform -version | head -1; ansible --version | head -1
