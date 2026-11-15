#!/bin/bash
# Practical 2 & 8 - manage the Terraform-created S3 bucket with Linux + AWS CLI commands.
set -e
cd "$(dirname "$0")/../terraform"
BUCKET=$(terraform output -raw s3_bucket)
echo ">> Bucket: $BUCKET"
mkdir -p /tmp/s3demo && cd /tmp/s3demo
echo "MediCart report generated $(date)" > report.txt
seq 1 5 | xargs -I{} sh -c 'echo "invoice {}" > invoice-{}.txt'
ls -l

echo ">> Upload single file";   aws s3 cp report.txt s3://$BUCKET/docs/report.txt
echo ">> Sync folder";          aws s3 sync . s3://$BUCKET/docs/
echo ">> List";                 aws s3 ls s3://$BUCKET/ --recursive --human-readable --summarize
echo ">> Versioning: overwrite report.txt"
echo "updated $(date)" > report.txt && aws s3 cp report.txt s3://$BUCKET/docs/report.txt
aws s3api list-object-versions --bucket $BUCKET --prefix docs/report.txt \
  --query 'Versions[].{Version:VersionId,Latest:IsLatest,Modified:LastModified}' --output table
echo ">> Download";             aws s3 cp s3://$BUCKET/docs/invoice-1.txt ./downloaded.txt && cat downloaded.txt
echo ">> Object metadata";      aws s3api head-object --bucket $BUCKET --key docs/report.txt --query "{Size:ContentLength,Encryption:ServerSideEncryption,Version:VersionId}" --output table
echo ">> Encryption config";    aws s3api get-bucket-encryption --bucket $BUCKET --output table
echo ">> Delete one object";    aws s3 rm s3://$BUCKET/docs/invoice-5.txt
aws s3 ls s3://$BUCKET/docs/
rm -rf /tmp/s3demo
