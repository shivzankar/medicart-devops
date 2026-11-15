# MediCart – Automated Cloud Deployment with Terraform, Ansible & Docker

**Course:** 21IPE333P Essentials in Cloud and DevOps
**Tools used:** Terraform · Ansible · Docker (+ AWS EC2, S3, EBS, IAM, CloudWatch, AWS CLI, Linux shell)

## Problem statement (VLE 6)
An e-commerce (online pharmacy) company faces frequent deployment failures, manual server
setup and downtime during releases. Servers are configured by hand, there is no monitoring,
and no backups.

## Solution
| Problem | Fix in MediCart |
|---|---|
| Manual server creation | **Terraform** creates EC2, EBS, S3, IAM, CloudWatch in one command |
| Manual configuration, "works on my machine" | **Ansible** configures the server identically every time |
| Dependency / environment mismatch | **Docker** packages the app; same image everywhere |
| Failed deployments go unnoticed | Health checks + **CloudWatch** alarms, logs and a dashboard |
| Data loss | Hourly **S3** backups (versioned + encrypted), data on a separate **EBS** volume |
| Over-privileged access | **IAM** least-privilege role, read-only developer group, IMDSv2 |

## Architecture
```
 Your PC (WSL)                                AWS (us-east-1)
 ─────────────                                ───────────────────────────────────────────
 terraform apply ───────────────────────────▶ EC2 (Ubuntu, t3.micro)  ◀── Security Group (22, 80)
                                              ├─ EBS 1 GB  → /data (logs)
                                              ├─ IAM role  → S3 + CloudWatch only
                                              S3 bucket (versioned, encrypted, lifecycle)
                                              CloudWatch: log groups, metric filter, alarms, dashboard, SNS
 ansible-playbook site.yml ── SSH ──────────▶ on EC2:
                                               common → ebs → docker → app → cloudwatch → backup
                                               ┌───────────── Docker ─────────────┐
 Browser ── HTTP :80 ───────────────────────▶ │ nginx  ──▶  medicart (Flask/gunicorn) │
                                               └──────────────────────────────────┘
                                               logs → CloudWatch agent → CloudWatch Logs
                                               cron hourly → tar → S3 backups/
```

## Project structure
```
app/          Flask online pharmacy (catalogue, cart, orders, /health, /metrics) + pytest tests
docker/       Dockerfile, docker-compose.yml (app + nginx), swarm-stack.yml, nginx.conf
terraform/    providers, variables, main (EC2/SG/EBS/key), s3, iam, cloudwatch, outputs
ansible/      site.yml + roles: common, ebs, docker, app, cloudwatch, backup; ping.yml
scripts/      deploy.sh, destroy.sh, aws-cli-infra.sh, s3-manage.sh, linux-basics.sh, load-test.sh
k8s/          pod.yaml (bonus – Practical 12)
```

## Practical / VLE coverage
| Item | Where |
|---|---|
| P1 EC2 | `terraform/main.tf` → `aws_instance.web` |
| P2 S3 | `terraform/s3.tf`, `scripts/s3-manage.sh` |
| P3 IAM | `terraform/iam.tf` (role, instance profile, group, user) |
| P4 CloudWatch | `terraform/cloudwatch.tf` (CPU/status alarms, dashboard) |
| P5 Linux / shell deployment | `scripts/linux-basics.sh`, `scripts/deploy.sh` |
| P6 EBS + S3 on EC2 | `aws_ebs_volume.data` + `ansible/roles/ebs` + `roles/backup` |
| P7 Terraform | `terraform/` |
| P8 S3 via Terraform + Linux | `terraform/s3.tf` + `scripts/s3-manage.sh` |
| P9 Ansible playbook | `ansible/ping.yml`, `ansible/site.yml` (common role) |
| P10 Website via Ansible | `ansible/roles/app` |
| P11 Docker + Swarm | `docker/` (Dockerfile, compose, swarm-stack) |
| P12 K8s Pod YAML | `k8s/pod.yaml` |
| VLE1 Static site + S3 backup + CloudWatch | app role + backup role + alarms |
| VLE2 Log monitoring | CloudWatch agent → `/medicart/app`, `/medicart/nginx`, metric filter `AppErrors`, alarm |
| VLE3 AWS CLI infra | `scripts/aws-cli-infra.sh` |
| VLE4 EC2 via Terraform + Ansible | `scripts/deploy.sh` (TF → inventory → Ansible) |
| VLE5 Cloud-native deploy + monitoring | Docker health check, `/health`, `/metrics`, dashboard |
| VLE6 E-commerce problem | this README (problem → solution) |

---

# How to run it (Windows + WSL)

> Run everything **inside WSL Ubuntu**, from the Linux home folder, **not** from `/mnt/c/...`.
> SSH refuses keys stored on the Windows drive because their permissions can't be locked down.

### 0. Copy the project into WSL and install tools (~10 min)
```bash
cp -r /mnt/c/Users/<YOUR-WINDOWS-USER>/Desktop/medicart-devops ~/
cd ~/medicart-devops
bash scripts/setup-tools-wsl.sh
```

### 1. Connect AWS credentials
* **Personal account:** IAM → Users → your user → Security credentials → Create access key, then `aws configure`
* **AWS Academy Learner Lab:** Start Lab → *AWS Details* → *AWS CLI: Show*, paste into `~/.aws/credentials`
  (the region must be `us-east-1`)

```bash
aws sts get-caller-identity     # 📸 screenshot
```

### 2. Configure Terraform
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Learner Lab → set lab_mode = true
nano terraform.tfvars
```

### 3. Deploy everything with one command
```bash
cd ~/medicart-devops
bash scripts/deploy.sh
```
This runs `terraform init/apply` → waits for SSH → `ansible-playbook site.yml`. It takes about 8–10 minutes.
Open the `website_url` it prints, add items to the cart and place an order.

*(To show each tool separately in the viva, run the steps by hand instead:
`cd terraform && terraform init && terraform plan && terraform apply`, then
`cd ../ansible && ansible-playbook ping.yml && ansible-playbook site.yml`.)*

### 4. Demos for the remaining practicals
```bash
# Linux commands on the server (P5)
IP=$(terraform -chdir=terraform output -raw public_ip)
scp -i ansible/medicart-key.pem scripts/linux-basics.sh ubuntu@$IP:~
ssh -i ansible/medicart-key.pem ubuntu@$IP 'bash linux-basics.sh'

# S3 management with Linux commands (P2, P8)
bash scripts/s3-manage.sh

# Generate traffic + errors for CloudWatch (P4, VLE2)
bash scripts/load-test.sh $IP 300
#  → AWS Console → CloudWatch → Dashboards → MediCart-Dashboard
#  → Log groups → /medicart/app   (search "ERROR")
#  → Alarms → medicart-app-errors goes to "In alarm" after ~5 min

# Infrastructure with AWS CLI only (VLE3)
bash scripts/aws-cli-infra.sh create
bash scripts/aws-cli-infra.sh status
bash scripts/aws-cli-infra.sh delete

# Docker + Swarm (P11) – on the EC2 server
ssh -i ansible/medicart-key.pem ubuntu@$IP
  docker ps; docker images; docker logs docker-app-1 --tail 5
  docker swarm init
  docker stack deploy -c /opt/medicart/docker/swarm-stack.yml medicart
  docker service ls; docker service scale medicart_app=5; docker service ps medicart_app
  curl localhost:8080/health
  docker stack rm medicart; docker swarm leave --force

# Kubernetes Pod (P12) – on your PC with minikube
minikube start
eval $(minikube docker-env) && docker build -t medicart:latest -f docker/Dockerfile .
kubectl apply -f k8s/pod.yaml && kubectl get pods -o wide
kubectl port-forward pod/medicart-pod 5000:5000      # open http://localhost:5000
```

### 5. Clean up (important – avoid charges)
```bash
bash scripts/destroy.sh
```

---

## 📸 Screenshot checklist for the report
1. `aws sts get-caller-identity`
2. `terraform plan` summary + `terraform apply` "Apply complete! Resources: N added"
3. `terraform output`
4. EC2 console – running instance, Storage tab showing 2 volumes
5. S3 console – bucket, Properties (versioning + encryption), `backups/` folder
6. IAM console – role with 2 policies, developer group + user
7. `ansible-playbook ping.yml` → `pong`
8. `ansible-playbook site.yml` → PLAY RECAP `failed=0`
9. Website in browser – home, cart, order placed, `/health`, `/metrics`
10. `linux-basics.sh` output (df showing `/data`)
11. `s3-manage.sh` output (versions table)
12. CloudWatch dashboard, log group with ERROR lines, alarms list
13. `aws-cli-infra.sh create` + website created by the CLI
14. `docker ps`, `docker service ls` (swarm with 5 replicas)
15. `kubectl get pods`
16. `terraform destroy` "Destroy complete!"

## Viva quick answers
* **Terraform vs Ansible?** Terraform *provisions* infrastructure (declarative, keeps state). Ansible *configures* servers (agentless, over SSH, idempotent).
* **Why Docker?** The same image runs identically everywhere. It's lightweight compared with a VM, starts quickly and is easy to roll back.
* **What is Terraform state?** A file mapping the code to real resources. It lets `plan` show what will change.
* **Idempotent?** Running the playbook again changes nothing if the server is already in the desired state.
* **EBS vs S3?** EBS is block storage attached to a single EC2 instance, like a disk. S3 is object storage accessed over HTTP, practically unlimited and durable.
* **IAM role vs user?** A role is assumed temporarily (by EC2) with no stored keys. A user is a long-term identity.
* **CloudWatch metric filter?** It turns matching log lines (here, `ERROR`) into a numeric metric you can alarm on.
* **Security measures:** least-privilege IAM, IMDSv2, encrypted EBS/S3, public access block on S3, non-root container, ufw firewall, generated secret key.
