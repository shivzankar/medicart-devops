output "website_url"       { value = "http://${aws_instance.web.public_ip}" }
output "public_ip"         { value = aws_instance.web.public_ip }
output "instance_id"       { value = aws_instance.web.id }
output "s3_bucket"         { value = terraform_data.backup_bucket.output }
output "ssh_command"       { value = "ssh -i ansible/medicart-key.pem ubuntu@${aws_instance.web.public_ip}" }
output "dashboard_url"     { value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=MediCart-Dashboard" }

# Auto-generate the Ansible inventory from Terraform outputs
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.ini"
  content  = <<-EOT
    [web]
    ${aws_instance.web.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=medicart-key.pem

    [web:vars]
    s3_bucket=${terraform_data.backup_bucket.output}
    aws_region=${var.region}
  EOT
}
