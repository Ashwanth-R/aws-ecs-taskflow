variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix applied to all resource names and tags"
  type        = string
  default     = "taskflow"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_password" {
  description = "PostgreSQL master password — do not commit; supply via TF_VAR_db_password or terraform.tfvars"
  type        = string
  sensitive   = true
}

variable "task_api_image_tag" {
  description = "ECR image tag to deploy for the Task API"
  type        = string
  default     = "latest"
}

variable "job_processor_image_tag" {
  description = "ECR image tag to deploy for the Job Processor"
  type        = string
  default     = "latest"
}

# Set either of these to 0 to pause the service and stop Fargate billing.
# Bring it back up by setting it to 1 and running terraform apply again.
variable "task_api_desired_count" {
  description = "Number of Task API tasks to run (0 = paused)"
  type        = number
  default     = 1
}

variable "job_processor_desired_count" {
  description = "Number of Job Processor tasks to run (0 = paused)"
  type        = number
  default     = 1
}
