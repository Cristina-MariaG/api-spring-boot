terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "springboot-api-tfstate"
    key            = "terraform.tfstate"
    region         = "eu-west-3"
    encrypt        = true
    dynamodb_table = "springboot-api-tf-lock"
  }
}

provider "aws" {
  region = var.aws_region
}

# Ubuntu 22.04 LTS AMI (dynamique selon la région)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Génère une paire de clés RSA 4096 bits
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Enregistre la clé publique sur AWS
resource "aws_key_pair" "deployer" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

# Sauvegarde la clé privée localement
resource "local_file" "private_key" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = "${path.module}/../${var.project_name}.pem"
  file_permission = "0600"
}

# Security Group
resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-sg"
  description = "Security group for ${var.project_name}"

  # SSH — uniquement depuis ton IP
  ingress {
    description = "SSH"
    from_port   = var.ssh_port
    to_port     = var.ssh_port
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # Application Spring Boot
  ingress {
    description = "Spring Boot App"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Tout le trafic sortant autorisé
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-sg"
    Environment = var.environment
  }
}

# Instance EC2
resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  tags = {
    Name        = "${var.project_name}-instance"
    Environment = var.environment
  }
}

# IP publique fixe (Elastic IP)
resource "aws_eip" "app_eip" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = {
    Name        = "${var.project_name}-eip"
    Environment = var.environment
  }
}
