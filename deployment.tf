# ***************** CONFIGURACIÓN BÁSICA ***********************

variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "project_prefix" {
  description = "Prefix used for naming AWS resources"
  type        = string
  default     = "cbd"
}

variable "instance_type" {
  description = "EC2 instance type for application hosts"
  type        = string
  default     = "t2.nano"
}

provider "aws" {
  region = var.region
}

locals {
  project_name = "${var.project_prefix}-circuit-breaker"
  repository   = "https://github.com/ISIS2503/ISIS2503-MonitoringApp.git"
  branch       = "Circuit-Breaker"

  common_tags = {
    Project   = local.project_name
    ManagedBy = "Terraform"
  }
}

# ***************** AMI UBUNTU ***********************

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ***************** INSTANCIAS MONITORING (NUEVAS) ***********************

resource "aws_instance" "monitoring" {
  for_each = toset(["b", "c"])  # 👈 SOLO crea 2 nuevas

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true

  # 👇 Usamos los security groups YA EXISTENTES
  vpc_security_group_ids = [
    "sg-09954f076294431f3", # django
    "sg-01442b9a03bea248c"  # ssh
  ]

  user_data = <<-EOT
              #!/bin/bash

              export DATABASE_HOST=172.31.24.42
              echo "DATABASE_HOST=172.31.24.42" >> /etc/environment

              apt-get update -y
              apt-get install -y python3-pip git build-essential libpq-dev python3-dev

              mkdir -p /labs
              cd /labs

              if [ ! -d ISIS2503-MonitoringApp ]; then
                git clone ${local.repository}
              fi

              cd ISIS2503-MonitoringApp
              git fetch origin ${local.branch}
              git checkout ${local.branch}

              pip3 install --upgrade pip --break-system-packages
              pip3 install -r requirements.txt --break-system-packages

              python3 manage.py makemigrations || true
              python3 manage.py migrate || true
              EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-monitoring-${each.key}"
    Role = "monitoring-app"
  })
}

# ***************** OUTPUTS ***********************

output "monitoring_public_ips" {
  description = "Public IPs of new monitoring instances"
  value       = { for id, instance in aws_instance.monitoring : id => instance.public_ip }
}

output "monitoring_private_ips" {
  description = "Private IPs of new monitoring instances"
  value       = { for id, instance in aws_instance.monitoring : id => instance.private_ip }
}
