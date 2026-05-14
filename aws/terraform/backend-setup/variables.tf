variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "springboot-api"
}

variable "bucket_name" {
  description = "Nom du bucket S3 (doit être unique globalement sur AWS)"
  type        = string
  default     = "springboot-api-tfstate"
}
