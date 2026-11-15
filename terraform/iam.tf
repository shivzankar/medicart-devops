# ---------------- IAM: least-privilege role for the EC2 instance ----------------
# Skipped in AWS Academy (lab_mode = true) where LabInstanceProfile is used instead.

locals {
  instance_profile_name = var.lab_mode ? "LabInstanceProfile" : one(aws_iam_instance_profile.ec2[*].name)
}

resource "aws_iam_role" "ec2" {
  count = var.lab_mode ? 0 : 1
  name  = "medicart-ec2-role-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "s3_backup" {
  count = var.lab_mode ? 0 : 1
  name  = "medicart-s3-backup"
  role  = aws_iam_role.ec2[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = local.bucket_arn },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = "${local.bucket_arn}/*" }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  count      = var.lab_mode ? 0 : 1
  role       = aws_iam_role.ec2[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2" {
  count = var.lab_mode ? 0 : 1
  name  = "medicart-ec2-profile-${random_id.suffix.hex}"
  role  = aws_iam_role.ec2[0].name
}

# ---------------- IAM: developer group with read-only access ----------------
resource "aws_iam_group" "developers" {
  count = var.lab_mode ? 0 : 1
  name  = "medicart-developers-${random_id.suffix.hex}"
}

resource "aws_iam_group_policy_attachment" "dev_readonly" {
  count      = var.lab_mode ? 0 : 1
  group      = aws_iam_group.developers[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_user" "dev" {
  count = var.lab_mode ? 0 : 1
  name  = "medicart-dev-${random_id.suffix.hex}"
}

resource "aws_iam_user_group_membership" "dev" {
  count  = var.lab_mode ? 0 : 1
  user   = aws_iam_user.dev[0].name
  groups = [aws_iam_group.developers[0].name]
}
