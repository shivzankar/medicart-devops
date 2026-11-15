#!/bin/bash
# =====================================================================
#  MediCart – run EVERYTHING end to end and capture evidence.
#    * runs every practical / VLE step
#    * saves full logs           -> docs/logs/NN-name.log
#    * takes real screenshots    -> Desktop\medicart-evidence\NN-name.png
#    * creates GitHub repo + pushes code and screenshots
#
#  Usage (inside WSL, Terminal MAXIMISED, don't touch the PC while it runs):
#      cd ~/medicart-devops && bash scripts/run-all.sh
#  Re-run a single step:   bash scripts/run-all.sh 12
# =====================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
REPO_NAME="${REPO_NAME:-medicart-devops}"
WINHOME=$(wslpath "$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')")
SHOTS="$WINHOME/Desktop/medicart-evidence"; LOGS="$ROOT/docs/logs"
mkdir -p "$SHOTS" "$LOGS"
KEY="$ROOT/ansible/medicart-key.pem"
SSHO="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
ONLY="${1:-}"
export GIT_TERMINAL_PROMPT=0
echo -ne "\033]0;MEDICART-RUN\007"   # window title, used to re-focus the terminal

C='\033[1;36m'; G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; N='\033[0m'

# ---------- helpers ----------
# PowerShell helper: captures ONLY the active window (terminal / Edge), not the whole screen
PS1="$SHOTS/.capture.ps1"
cat > "$PS1" <<'PSEOF'
param([string]$Out)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int s);
  public struct RECT { public int L, T, R, B; }
}
"@
[W]::SetProcessDPIAware() | Out-Null
$r = New-Object W+RECT
[W]::DwmGetWindowAttribute([W]::GetForegroundWindow(), 9, [ref]$r, 16) | Out-Null
$w = $r.R - $r.L; $h = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
PSEOF
shot() {   # shot <name> : PNG of the active window
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$PS1")" -Out "$(wslpath -w "$SHOTS")\\$1.png" >/dev/null 2>&1 \
    && echo -e "${G}   📸 saved $1.png${N}" >&2
}
focus_terminal() { powershell.exe -NoProfile -Command "(New-Object -ComObject WScript.Shell).AppActivate('MEDICART-RUN')" >/dev/null 2>&1; sleep 1; }
browser() {  # browser <name> <url>
  cmd.exe /c start "" msedge --new-window --start-maximized "$2" >/dev/null 2>&1; sleep 7; shot "$1"; focus_terminal
}
banner() { clear; echo -e "${C}════════════════════════════════════════════════════════════════════════════${N}";
           echo -e "${C} MediCart DevOps | $1${N}"; echo -e "${C}════════════════════════════════════════════════════════════════════════════${N}"; }
# screen <name> <title> <logfile> [lines]  : clear, show the tail of a log, screenshot it
screen() { banner "$2"; local n=${4:-$(( $(tput lines) - 5 ))}; tail -n "$n" "$3" | sed 's/\x1b\[[0-9;]*m//g'; sleep 1; shot "$1"; }
# run <logfile> <cmd...> : print command, run it live, save output
run() { local log=$1; shift; echo -e "${Y}\$ $*${N}" | tee -a "$log"; bash -c "$*" 2>&1 | tee -a "$log"; return "${PIPESTATUS[0]}"; }
want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }
ip()   { terraform -chdir=terraform output -raw public_ip 2>/dev/null; }
bucket(){ terraform -chdir=terraform output -raw s3_bucket 2>/dev/null; }
sshc() { ssh $SSHO -i "$KEY" ubuntu@"$(ip)" "$@"; }
fail() { echo -e "${R}✗ $*${N}"; exit 1; }

# =====================================================================
if want 0; then L=$LOGS/00-tools.log; : >$L
  run $L 'command -v terraform >/dev/null && command -v ansible >/dev/null && command -v aws >/dev/null || bash scripts/setup-tools-wsl.sh'
  { echo "\$ lsb_release -d"; lsb_release -d; echo "\$ aws --version"; aws --version
    echo "\$ terraform -version"; terraform -version | head -1; echo "\$ ansible --version"; ansible --version | head -1
    echo "\$ docker --version"; docker --version; echo "\$ kubectl version --client"; kubectl version --client 2>/dev/null | head -1
    echo "\$ minikube version"; minikube version 2>/dev/null | head -1; echo "\$ git --version"; git --version; } >>$L 2>&1
  screen 00-tools "Step 0 - Tool versions" $L 16
fi

if want 1; then L=$LOGS/01-aws-identity.log; : >$L
  run $L 'aws sts get-caller-identity --output table' || fail "AWS credentials not set. Run 'aws configure' (or paste Learner Lab creds into ~/.aws/credentials) then re-run."
  run $L 'aws configure get region || echo "(no default region - using us-east-1)"'
  screen 01-aws-identity "Step 1 - AWS credentials verified" $L
fi

if want 2; then L=$LOGS/02-terraform-init-plan.log; : >$L
  if [ ! -f terraform/terraform.tfvars ]; then
    LAB=false; aws sts get-caller-identity --query Arn --output text | grep -qiE 'voclabs|LabRole' && LAB=true
    MYIP=$(curl -s https://checkip.amazonaws.com | tr -d '\n')
    printf 'region        = "us-east-1"\ninstance_type = "t3.micro"\nlab_mode      = %s\nmy_ip_cidr    = "%s/32"\nalert_email   = ""\n' $LAB "$MYIP" > terraform/terraform.tfvars
  fi
  run $L 'cat terraform/terraform.tfvars'
  run $L 'terraform -chdir=terraform init -input=false -no-color' || fail "terraform init failed"
  run $L 'terraform -chdir=terraform validate -no-color'
  run $L 'terraform -chdir=terraform plan -no-color -out=tfplan | grep -E "will be created|Plan:"'
  screen 02-terraform-plan "Step 2 - Terraform init / validate / plan" $L
fi

if want 3; then L=$LOGS/03-terraform-apply.log; : >$L
  run $L 'terraform -chdir=terraform apply -no-color -auto-approve tfplan 2>/dev/null || terraform -chdir=terraform apply -no-color -auto-approve' || fail "terraform apply failed - see $L"
  screen 03-terraform-apply "Step 3 - Terraform apply (infrastructure created)" $L 25
  L2=$LOGS/03b-terraform-output.log; : >$L2
  run $L2 'terraform -chdir=terraform output -no-color'
  run $L2 'terraform -chdir=terraform state list'
  run $L2 'cat ansible/inventory.ini'
  screen 03b-terraform-output "Step 3b - Terraform outputs, state & generated Ansible inventory" $L2
fi

if want 4; then L=$LOGS/04-ansible-ping.log; : >$L; chmod 600 "$KEY"
  echo "Waiting for SSH on $(ip) ..."
  for i in $(seq 1 30); do ssh $SSHO -o ConnectTimeout=5 -i "$KEY" ubuntu@"$(ip)" true 2>/dev/null && break; sleep 10; done
  (cd ansible && run $L 'ANSIBLE_FORCE_COLOR=0 ansible-playbook ping.yml')
  screen 04-ansible-ping "Step 4 - Ansible connectivity test (ping.yml)" $L
fi

if want 5; then L=$LOGS/05-ansible-site.log; : >$L
  (cd ansible && run $L 'ANSIBLE_FORCE_COLOR=0 ansible-playbook site.yml') || fail "ansible failed - see $L"
  screen 05a-ansible-site "Step 5 - Ansible site.yml (common, ebs, docker, app, cloudwatch, backup)" $L
  banner "Step 5b - Ansible tasks executed"
  grep -E '^TASK \[' $L | sed 's/\*//g' | tail -n $(( $(tput lines) - 5 )); shot 05b-ansible-tasks
fi

if want 6; then L=$LOGS/06-website.log; : >$L; IP=$(ip); J=/tmp/mc-cookies
  run $L "curl -s http://$IP/health; echo"
  run $L "curl -s -c $J -b $J -X POST http://$IP/cart/add/1 -o /dev/null; curl -s -c $J -b $J -X POST http://$IP/cart/add/2 -o /dev/null; curl -s -c $J -b $J -X POST http://$IP/cart/add/5 -o /dev/null; curl -s -c $J -b $J -X POST -d name=Shiv http://$IP/checkout | grep -o 'Order [A-Z0-9]* placed'"
  run $L "curl -s http://$IP/metrics; echo"
  run $L "curl -sI http://$IP/ | head -5"
  screen 06-website-curl "Step 6 - Website live on EC2 (health, order, metrics)" $L
  browser 06b-browser-home   "http://$IP/"
  browser 06c-browser-orders "http://$IP/orders"
  browser 06d-browser-health "http://$IP/health"
  browser 06e-browser-metrics "http://$IP/metrics"
fi

if want 7; then L=$LOGS/07-ec2-ebs.log; : >$L; ID=$(terraform -chdir=terraform output -raw instance_id)
  run $L "aws ec2 describe-instances --instance-ids $ID --query 'Reservations[0].Instances[0].{ID:InstanceId,Type:InstanceType,State:State.Name,IP:PublicIpAddress,AZ:Placement.AvailabilityZone,IMDS:MetadataOptions.HttpTokens}' --output table"
  run $L "aws ec2 describe-volumes --filters Name=attachment.instance-id,Values=$ID --query 'Volumes[].{Vol:VolumeId,Size:Size,Type:VolumeType,Encrypted:Encrypted,Device:Attachments[0].Device}' --output table"
  run $L "aws ec2 describe-security-groups --filters Name=group-name,Values=medicart-sg-* --query 'SecurityGroups[0].IpPermissions[].{Port:FromPort,CIDR:IpRanges[0].CidrIp}' --output table"
  screen 07a-ec2-ebs "Step 7 - EC2 instance, EBS volumes, security group (P1, P6)" $L
  L2=$LOGS/07b-ebs-on-server.log; : >$L2
  run $L2 "ssh $SSHO -i $KEY ubuntu@$(ip) 'lsblk; echo; df -h / /data; echo; grep /data /etc/fstab; echo; ls -l /data/logs /data/logs/app'"
  screen 07b-ebs-mounted "Step 7b - EBS volume formatted and mounted at /data" $L2
fi

if want 8; then L=$LOGS/08-iam.log; : >$L
  if grep -q 'lab_mode *= *true' terraform/terraform.tfvars; then
    run $L "aws ec2 describe-instances --instance-ids $(terraform -chdir=terraform output -raw instance_id) --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' --output text"
    run $L "aws iam list-attached-role-policies --role-name LabRole --output table 2>&1 | head -20"
  else
    R=$(aws iam list-roles --query "Roles[?starts_with(RoleName,'medicart-ec2-role')].RoleName" --output text)
    G=$(aws iam list-groups --query "Groups[?starts_with(GroupName,'medicart-developers')].GroupName" --output text)
    run $L "aws iam get-role --role-name $R --query 'Role.{Role:RoleName,Arn:Arn,Created:CreateDate}' --output table"
    run $L "aws iam list-attached-role-policies --role-name $R --output table"
    run $L "aws iam get-role-policy --role-name $R --policy-name medicart-s3-backup --query PolicyDocument --output json"
    run $L "aws iam get-group --group-name $G --query '{Group:Group.GroupName,Users:Users[].UserName}' --output table"
    run $L "aws iam list-attached-group-policies --group-name $G --output table"
  fi
  run $L "ssh $SSHO -i $KEY ubuntu@$(ip) 'aws sts get-caller-identity --output table'"
  screen 08-iam "Step 8 - IAM: least-privilege instance role + developer group (P3)" $L
fi

if want 9; then L=$LOGS/09-s3-manage.log; : >$L
  run $L 'bash scripts/s3-manage.sh'
  screen 09a-s3-manage "Step 9 - Manage Terraform S3 bucket with Linux + AWS CLI (P2, P8)" $L
  L2=$LOGS/09b-s3-props.log; : >$L2; B=$(bucket)
  run $L2 "aws s3api get-bucket-versioning --bucket $B --output table"
  run $L2 "aws s3api get-public-access-block --bucket $B --output table"
  run $L2 "aws s3api get-bucket-lifecycle-configuration --bucket $B --query 'Rules[0].{ID:ID,Status:Status,Prefix:Filter.Prefix}' --output table"
  run $L2 "aws s3 ls s3://$B/backups/ --human-readable"
  screen 09b-s3-properties "Step 9b - S3 versioning, public-access block, lifecycle, backups (VLE1)" $L2
fi

if want 10; then L=$LOGS/10-linux.log; : >$L
  scp $SSHO -i "$KEY" scripts/linux-basics.sh ubuntu@"$(ip)":~ >/dev/null
  run $L "ssh $SSHO -i $KEY ubuntu@$(ip) 'bash linux-basics.sh'"
  H=$(( $(tput lines) - 5 )); T=$(wc -l < $L)
  banner "Step 10a - Linux commands on EC2 (P5)"; head -n $H $L; shot 10a-linux-1
  banner "Step 10b - Linux commands on EC2 (P5)"; tail -n +$((H+1)) $L | head -n $H; shot 10b-linux-2
  [ $T -gt $((2*H)) ] && { banner "Step 10c - Linux commands on EC2 (P5)"; tail -n $H $L; shot 10c-linux-3; }
fi

if want 11; then L=$LOGS/11-cloudwatch.log; : >$L; IP=$(ip)
  run $L "bash scripts/load-test.sh $IP 200 | tail -3"
  echo "Waiting 2 minutes for logs/metrics to reach CloudWatch..."; sleep 120
  run $L "aws logs describe-log-groups --log-group-name-prefix /medicart --query 'logGroups[].{Group:logGroupName,Retention:retentionInDays,Bytes:storedBytes}' --output table"
  run $L "aws logs describe-metric-filters --log-group-name /medicart/app --query 'metricFilters[].{Filter:filterName,Pattern:filterPattern,Metric:metricTransformations[0].metricName}' --output table"
  run $L "aws cloudwatch describe-alarms --alarm-name-prefix medicart --query 'MetricAlarms[].{Alarm:AlarmName,Metric:MetricName,Threshold:Threshold,State:StateValue}' --output table"
  run $L "aws cloudwatch list-dashboards --query 'DashboardEntries[].DashboardName' --output text"
  screen 11a-cloudwatch "Step 11 - CloudWatch log groups, metric filter, alarms, dashboard (P4)" $L
  L2=$LOGS/11b-cloudwatch-logs.log; : >$L2
  run $L2 "aws logs filter-log-events --log-group-name /medicart/app --filter-pattern ERROR --max-items 8 --query 'events[].message' --output text | tr '\t' '\n' | head -8"
  run $L2 "aws logs filter-log-events --log-group-name /medicart/nginx --max-items 6 --query 'events[].message' --output text | tr '\t' '\n' | cut -c1-140 | head -6"
  run $L2 "aws cloudwatch get-metric-statistics --namespace MediCart --metric-name AppErrors --start-time \$(date -u -d '-30 min' +%FT%TZ) --end-time \$(date -u +%FT%TZ) --period 300 --statistics Sum --output table"
  run $L2 "aws cloudwatch list-metrics --namespace MediCart --query 'Metrics[].MetricName' --output text"
  screen 11b-cloudwatch-logs "Step 11b - Log monitoring: app ERROR lines & nginx logs in CloudWatch (VLE2)" $L2
fi

if want 12; then L=$LOGS/12-docker.log; : >$L
  run $L "ssh $SSHO -i $KEY ubuntu@$(ip) 'docker --version; docker compose version; echo; docker images; echo; docker ps --format \"table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\"; echo; docker inspect --format \"{{.Name}} health={{.State.Health.Status}} user={{.Config.User}}\" docker-app-1'"
  screen 12a-docker "Step 12 - Docker images & containers on EC2 (P11)" $L
  L2=$LOGS/12b-swarm.log; : >$L2
  run $L2 "ssh $SSHO -i $KEY ubuntu@$(ip) 'docker swarm init >/dev/null 2>&1; docker node ls; docker stack deploy -c /opt/medicart/docker/swarm-stack.yml medicart; sleep 15; docker service ls; docker service scale medicart_app=5; sleep 10; docker service ps medicart_app --format \"table {{.Name}}\t{{.CurrentState}}\"; curl -s localhost:8080/health; echo'"
  screen 12b-swarm "Step 12b - Docker Swarm: stack deploy + scale to 5 replicas (P11)" $L2
  sshc 'docker stack rm medicart >/dev/null; sleep 5; docker swarm leave --force >/dev/null' 2>/dev/null
fi

if want 13; then L=$LOGS/13-kubernetes.log; : >$L
  minikube status >/dev/null 2>&1 || run $L 'minikube start --driver=docker'
  run $L 'eval $(minikube docker-env) && docker build -q -t medicart:latest -f docker/Dockerfile .'
  run $L 'kubectl delete pod medicart-pod --ignore-not-found >/dev/null; kubectl apply -f k8s/pod.yaml && kubectl wait --for=condition=Ready pod/medicart-pod --timeout=120s'
  run $L 'kubectl get pods -o wide'
  run $L 'kubectl describe pod medicart-pod | grep -E "^Name:|^Status:|Image:|Liveness|Limits|cpu|memory" | head -10'
  kubectl port-forward pod/medicart-pod 5055:5000 >/dev/null 2>&1 & PF=$!; sleep 4
  run $L 'curl -s localhost:5055/health; echo'; kill $PF 2>/dev/null
  screen 13-kubernetes "Step 13 - Kubernetes Pod YAML on minikube (P12)" $L
fi

if want 14; then L=$LOGS/14-aws-cli.log; : >$L
  (cd scripts && run $L 'bash aws-cli-infra.sh create') || true
  screen 14a-aws-cli-create "Step 14 - Infrastructure created with AWS CLI only (VLE3)" $L
  CIP=$(grep '^IP=' scripts/.cli-infra.state | cut -d= -f2); echo "Waiting for nginx on $CIP..."
  for i in $(seq 1 24); do curl -s -m 3 "http://$CIP" | grep -q MediCart && break; sleep 10; done
  L2=$LOGS/14b-aws-cli-status.log; : >$L2
  (cd scripts && run $L2 'bash aws-cli-infra.sh status'); run $L2 "curl -s http://$CIP; echo"
  screen 14b-aws-cli-status "Step 14b - AWS CLI infra status + website" $L2
  browser 14c-browser-cli-site "http://$CIP/"
  L3=$LOGS/14d-aws-cli-delete.log; : >$L3
  (cd scripts && run $L3 'bash aws-cli-infra.sh delete')
  screen 14d-aws-cli-delete "Step 14d - AWS CLI infra deleted (clean-up)" $L3
fi

if want 15; then L=$LOGS/15-backup.log; : >$L
  run $L "ssh $SSHO -i $KEY ubuntu@$(ip) 'crontab -l 2>/dev/null; sudo crontab -l; sudo /usr/local/bin/medicart-backup.sh; tail -3 /data/logs/backup.log'"
  run $L "aws s3 ls s3://$(bucket)/backups/ --human-readable --summarize"
  screen 15-backup "Step 15 - Automated hourly backup EC2 -> S3 (VLE1)" $L
fi

if want 16; then L=$LOGS/16-github.log; : >$L
  mkdir -p docs/screenshots && cp "$SHOTS"/*.png docs/screenshots/ 2>/dev/null
  rm -f terraform/tfplan
  [ -d .git ] || { git init -q -b main; }
  git add -A && git commit -qm "MediCart: Terraform + Ansible + Docker deployment on AWS with evidence" || true
  USER_GH=""
  if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
    USER_GH=$(gh api user -q .login)
    gh repo view "$USER_GH/$REPO_NAME" >/dev/null 2>&1 || run $L "gh repo create $REPO_NAME --public --description 'MediCart: automated AWS deployment with Terraform, Ansible and Docker' --source=. --remote=origin"
  else
    TOKEN=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')
    [ -z "$TOKEN" ] && fail "No GitHub credentials found. Run: gh auth login   (then re-run: bash scripts/run-all.sh 16)"
    USER_GH=$(curl -s -H "Authorization: token $TOKEN" https://api.github.com/user | sed -n 's/.*"login": *"\([^"]*\)".*/\1/p')
    curl -s -o /dev/null -w "create repo: HTTP %{http_code}\n" -H "Authorization: token $TOKEN" https://api.github.com/user/repos \
      -d "{\"name\":\"$REPO_NAME\",\"description\":\"MediCart: automated AWS deployment with Terraform, Ansible and Docker\",\"private\":false}" | tee -a $L
  fi
  git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$USER_GH/$REPO_NAME.git"
  run $L 'git push -u origin main 2>&1 | tail -4'
  run $L 'git log --oneline | head -5; git remote -v | head -1'
  run $L 'git ls-files | head -60 | column -c 160'
  echo "https://github.com/$USER_GH/$REPO_NAME" > docs/logs/repo-url.txt
  screen 16a-github-push "Step 16 - Code pushed to GitHub ($USER_GH/$REPO_NAME)" $L
  browser 16b-browser-github "https://github.com/$USER_GH/$REPO_NAME"
  cp "$SHOTS"/16*.png docs/screenshots/ 2>/dev/null; git add -A; git commit -qm "Add GitHub screenshots" && git push -q
fi

# copy logs next to the screenshots for the report
cp -r "$LOGS" "$SHOTS/" 2>/dev/null
[ -n "$ONLY" ] && { echo -e "${G}Step $ONLY finished.${N}"; exit 0; }
banner "ALL DONE ✅"
echo -e "${G}Website   :${N} http://$(ip)"
echo -e "${G}Evidence  :${N} Desktop\\medicart-evidence  ($(ls "$SHOTS"/*.png 2>/dev/null | wc -l) screenshots)"
[ -f docs/logs/repo-url.txt ] && echo -e "${G}GitHub    :${N} $(cat docs/logs/repo-url.txt)"
echo -e "${Y}When finished with the demo/viva:  bash scripts/destroy.sh${N}"
