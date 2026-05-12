variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "staging"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "springboot-api"
}

variable "ssh_port" {
  description = "SSH port"
  type        = number
  default     = 22
}

variable "my_ip" {
  description = "Your public IP for SSH access (format: x.x.x.x/32)"
  type        = string
}

variable "app_port" {
  description = "Application port exposed by the Spring Boot app"
  type        = number
  default     = 8081
}
