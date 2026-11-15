#!/bin/bash
# ============================================================
#  VLE 3 - Infrastructure creation using ONLY the AWS CLI
#   ./aws-cli-infra.sh create   -> SG + key pair + EC2 (with nginx) + S3
#   ./aws-cli-infra.sh status
#   ./aws-cli-infra.sh delete   -> removes everything it created
# ============================================================
set -euo pipefail
REGION=${AWS_REGION:-us-east-1}
NAME=medicart-cli
STATE=$(dirname "$0")/.cli-infra.state
export AWS_DEFAULT_REGION=$REGION

create() {
  SUFFIX=$RANDOM
  VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
  echo "Default VPC: $VPC"

  SG=$(aws ec2 create-security-group --group-name $NAME-sg-$SUFFIX --description "CLI demo" \
        --vpc-id $VPC --query GroupId --output text)
  aws ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 22 --cidr 0.0.0.0/0
  aws ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 80 --cidr 0.0.0.0/0
  echo "Security group: $SG"

  aws ec2 create-key-pair --key-name $NAME-key-$SUFFIX --query KeyMaterial --output text > $NAME-key.pem
  chmod 600 $NAME-key.pem
  echo "Key pair: $NAME-key-$SUFFIX (saved to $NAME-key.pem)"

  AMI=$(aws ssm get-parameter --name /aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id \
        --query Parameter.Value --output text)
  cat > /tmp/userdata.sh <<'UD'
#!/bin/bash
apt-get update -y && apt-get install -y nginx
echo "<h1>MediCart - created with AWS CLI</h1><p>Host: $(hostname)</p>" > /var/www/html/index.html
UD
  INSTANCE=$(aws ec2 run-instances --image-id $AMI --instance-type t3.micro --key-name $NAME-key-$SUFFIX \
     --security-group-ids $SG --user-data file:///tmp/userdata.sh \
     --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME-ec2}]" \
     --query 'Instances[0].InstanceId' --output text)
  echo "Instance: $INSTANCE - waiting until running..."
  aws ec2 wait instance-running --instance-ids $INSTANCE
  IP=$(aws ec2 describe-instances --instance-ids $INSTANCE --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

  BUCKET=$NAME-bucket-$SUFFIX-$(date +%s)
  if [ "$REGION" = "us-east-1" ]; then aws s3api create-bucket --bucket $BUCKET >/dev/null
  else aws s3api create-bucket --bucket $BUCKET --create-bucket-configuration LocationConstraint=$REGION >/dev/null; fi
  aws s3api put-bucket-versioning --bucket $BUCKET --versioning-configuration Status=Enabled
  echo "S3 bucket: $BUCKET"

  aws cloudwatch put-metric-alarm --alarm-name $NAME-cpu-$SUFFIX --namespace AWS/EC2 --metric-name CPUUtilization \
     --dimensions Name=InstanceId,Value=$INSTANCE --statistic Average --period 300 --evaluation-periods 1 \
     --threshold 70 --comparison-operator GreaterThanThreshold
  echo "CloudWatch alarm: $NAME-cpu-$SUFFIX"

  printf "SG=%s\nKEY=%s\nINSTANCE=%s\nBUCKET=%s\nALARM=%s\nIP=%s\n" \
     $SG $NAME-key-$SUFFIX $INSTANCE $BUCKET $NAME-cpu-$SUFFIX $IP > $STATE
  echo "=========================================="
  echo " Done. Website (ready in ~2 min): http://$IP"
  echo "=========================================="
}

status() {
  source $STATE
  aws ec2 describe-instances --instance-ids $INSTANCE \
    --query 'Reservations[0].Instances[0].{ID:InstanceId,State:State.Name,Type:InstanceType,IP:PublicIpAddress}' --output table
  aws s3 ls | grep $BUCKET
  aws cloudwatch describe-alarms --alarm-names $ALARM --query 'MetricAlarms[0].{Alarm:AlarmName,State:StateValue}' --output table
}

delete() {
  source $STATE
  aws cloudwatch delete-alarms --alarm-names $ALARM
  aws ec2 terminate-instances --instance-ids $INSTANCE >/dev/null
  echo "Terminating $INSTANCE..."; aws ec2 wait instance-terminated --instance-ids $INSTANCE
  aws ec2 delete-security-group --group-id $SG
  aws ec2 delete-key-pair --key-name $KEY; rm -f $NAME-key.pem
  aws s3 rb s3://$BUCKET --force 2>/dev/null || {
    aws s3api delete-objects --bucket $BUCKET --delete "$(aws s3api list-object-versions --bucket $BUCKET \
      --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json)" >/dev/null 2>&1 || true
    aws s3 rb s3://$BUCKET --force; }
  rm -f $STATE; echo "All CLI resources deleted."
}

case "${1:-}" in create) create;; status) status;; delete) delete;; *) echo "Usage: $0 create|status|delete";; esac
