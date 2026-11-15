# ======================================================================
#  MediCart infrastructure: EC2 + EBS + S3 + IAM + Security Group
# ======================================================================

data "aws_vpc" "default" { default = true }

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "random_id" "suffix" { byte_length = 3 }

# ---------------- SSH key pair (private key saved for Ansible) ----------------
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "medicart" {
  key_name   = "medicart-key-${random_id.suffix.hex}"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/../ansible/medicart-key.pem"
  file_permission = "0600"
}

# ---------------- Security group ----------------
resource "aws_security_group" "web" {
  name        = "medicart-sg-${random_id.suffix.hex}"
  description = "MediCart web server"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------- EC2 instance ----------------
resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.medicart.key_name
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = local.instance_profile_name
  monitoring             = false

  root_block_device {
    volume_size = 12
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 only (security best practice)
  }

  tags = { Name = "medicart-web" }
}

# ---------------- Extra EBS volume (mounted at /data by Ansible) ----------------
resource "aws_ebs_volume" "data" {
  availability_zone = aws_instance.web.availability_zone
  size              = 1
  type              = "gp3"
  encrypted         = true
  tags              = { Name = "medicart-data" }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.web.id
  # don't try to detach a mounted disk on destroy; it is deleted after the instance terminates
  skip_destroy = true
}
