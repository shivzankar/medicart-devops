# ---------------- S3 backup bucket ----------------
# NOTE: AWS Academy Learner Lab denies s3:GetBucketObjectLockConfiguration via an SCP,
# and the aws_s3_bucket resource always reads that setting -> "AccessDenied".
# Work-around: Terraform creates/deletes the bucket through the AWS CLI (terraform_data),
# while versioning, encryption, public-access block and lifecycle stay normal Terraform resources.
locals {
  bucket_name = "medicart-backup-${random_id.suffix.hex}"
  bucket_arn  = "arn:aws:s3:::${local.bucket_name}"
  location    = var.region == "us-east-1" ? "" : "--create-bucket-configuration LocationConstraint=${var.region}"
}

resource "terraform_data" "backup_bucket" {
  input = local.bucket_name

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "aws s3api head-bucket --bucket ${self.input} 2>/dev/null || aws s3api create-bucket --bucket ${self.input} --region ${var.region} ${local.location}"
  }

  # on destroy: delete every object version, then the bucket
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      B=${self.input}
      V=$(aws s3api list-object-versions --bucket $B --output json --query '{Objects: [Versions[], DeleteMarkers[]][].{Key:Key,VersionId:VersionId}}' 2>/dev/null)
      echo "$V" | grep -q VersionId && aws s3api delete-objects --bucket $B --delete "$V" >/dev/null
      aws s3 rb s3://$B --force || true
    EOT
  }
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = terraform_data.backup_bucket.output
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = terraform_data.backup_bucket.output
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket                  = terraform_data.backup_bucket.output
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = terraform_data.backup_bucket.output
  rule {
    id     = "expire-old-backups"
    status = "Enabled"
    filter { prefix = "backups/" }
    noncurrent_version_expiration { noncurrent_days = 30 }
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}
