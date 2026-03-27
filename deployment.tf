# Variable. Define la región de AWS donde se desplegará la infraestructura.
variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

# Variable. Define el prefijo usado para nombrar los recursos en AWS.
variable "project_prefix" {
  description = "Prefix used for naming AWS resources"
  type        = string
  default     = "cbd"
}

# Variable. Define el tipo de instancia EC2 a usar para las máquinas virtuales.
variable "instance_type" {
  description = "EC2 instance type for application hosts"
  type        = string
  default     = "t2.nano"
}

# Proveedor. Define el proveedor de infraestructura (AWS) y la región.
provider "aws" {
  region = var.region
}

# Variables locales usadas en la configuración de Terraform.
locals {
  project_name = "${var.project_prefix}-circuit-breaker"
  repository   = "https://github.com/ISIS2503/ISIS2503-MonitoringApp.git"
  branch       = "Circuit-Breaker"

  common_tags = {
    Project   = local.project_name
    ManagedBy = "Terraform"
  }
}

# Data Source. Busca la AMI más reciente de Ubuntu 24.04 usando los filtros especificados.
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

# Recurso. Define el grupo de seguridad para el tráfico de Django (8080).
resource "aws_security_group" "traffic_django" {
    name        = "${var.project_prefix}-traffic-django"
    description = "Allow application traffic on port 8080"

    ingress {
        description = "HTTP access for service layer"
        from_port   = 8080
        to_port     = 8080
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = merge(local.common_tags, {
        Name = "${var.project_prefix}-traffic-services"
    })
}

# Recurso. Define el grupo de seguridad para el tráfico del Circuit Breaker (8000, 8001).
resource "aws_security_group" "traffic_cb" {
  name        = "${var.project_prefix}-traffic-cb"
  description = "Expose Kong circuit breaker ports"

  ingress {
    description = "Kong traffic"
    from_port   = 8000
    to_port     = 8001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-traffic-cb"
  })
}

# Recurso. Define el grupo de seguridad para el tráfico de la base de datos (5432).
resource "aws_security_group" "traffic_db" {
  name        = "${var.project_prefix}-traffic-db"
  description = "Allow PostgreSQL access"

  ingress {
    description = "Traffic from anywhere to DB"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-traffic-db"
  })
}

# Recurso. Define el grupo de seguridad para el tráfico SSH (22) y permite todo el tráfico saliente.
resource "aws_security_group" "traffic_ssh" {
  name        = "${var.project_prefix}-traffic-ssh"
  description = "Allow SSH access"

  ingress {
    description = "SSH access from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-traffic-ssh"
  })
}


resource "aws_instance" "monitoring" {
  for_each = toset(["b", "c"])  #

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [
    aws_security_group.traffic_django.id,
    aws_security_group.traffic_ssh.id
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

              python3 manage.py makemigrations
              python3 manage.py migrate
              EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-monitoring-${each.key}"
    Role = "monitoring-app"
  })
}



