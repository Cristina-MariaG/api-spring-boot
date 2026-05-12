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

variable "dynamodb_table_name" {
  description = "Nom de la table DynamoDB pour le verrou Terraform"
  type        = string
  default     = "springboot-api-tf-lock"
}
