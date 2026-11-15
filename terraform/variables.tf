variable "region" {
  description = "AWS region (AWS Academy Learner Lab only allows us-east-1 / us-west-2)"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "Free-tier eligible type (t2.micro or t3.micro)"
  type        = string
  default     = "t3.micro"
}

variable "lab_mode" {
  description = "true = AWS Academy Learner Lab (can't create IAM roles/users, uses LabInstanceProfile)"
  type        = bool
  default     = false
}

variable "my_ip_cidr" {
  description = "Your public IP for SSH, e.g. 49.37.10.5/32 (curl ifconfig.me). 0.0.0.0/0 = open to all"
  type        = string
  default     = "0.0.0.0/0"
}

variable "alert_email" {
  description = "Email for CloudWatch alarm notifications (leave empty to skip)"
  type        = string
  default     = ""
}
