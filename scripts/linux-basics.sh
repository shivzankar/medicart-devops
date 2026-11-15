#!/bin/bash
# Practical 5 - Linux commands demo. Run ON the EC2 instance:
#   scp -i ansible/medicart-key.pem scripts/linux-basics.sh ubuntu@<IP>:~ && ssh ... 'bash linux-basics.sh'
section() { echo; echo "==================== $* ===================="; }
section "System info";        uname -a; hostname; uptime; whoami
section "OS release";         cat /etc/os-release | head -3
section "CPU / Memory";       nproc; free -h
section "Disks (note /data = EBS volume)"; df -h | grep -E 'Filesystem|/$|/data'; lsblk
section "Network";            ip -brief addr; ss -tulpn 2>/dev/null | grep -E ':80|:22' || true
section "Processes (top 5 by memory)"; ps aux --sort=-%mem | head -6
section "Files & permissions"
mkdir -p ~/demo && cd ~/demo && echo "hello medicart" > file.txt
ls -l file.txt; chmod 640 file.txt; ls -l file.txt; cp file.txt copy.txt; mv copy.txt renamed.txt; ls
grep -n medicart file.txt; wc -l file.txt; cd ~ && rm -rf ~/demo
section "Users & groups";     id; getent group docker
section "Services";           systemctl is-active docker amazon-cloudwatch-agent 2>/dev/null
section "Docker containers";  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null
section "App logs (last 5)";  tail -5 /data/logs/app/app.log 2>/dev/null
section "Health check";       curl -s localhost/health; echo
