# SSM Parameter Store — stores secrets so they are never baked into task definitions
# or environment variable config. ECS fetches these at task launch and injects
# them as env vars; the container code sees them as ordinary environment variables.

resource "aws_ssm_parameter" "database_url" {
  name        = "/${local.name_prefix}/database-url"
  type        = "SecureString"
  description = "PostgreSQL connection string for the Task API"

  # Terraform builds this from the RDS endpoint once the instance is created.
  # The password comes from var.db_password, which is marked sensitive and
  # never appears in plan output or logs.
  value = "postgresql://taskflow:${var.db_password}@${aws_db_instance.postgres.address}:5432/taskflow"
}

resource "aws_ssm_parameter" "processor_base_url" {
  name        = "/${local.name_prefix}/processor-base-url"
  type        = "String"
  description = "Cloud Map private DNS name for the Job Processor"

  # This matches the Cloud Map namespace and service name defined in cloudmap.tf.
  # The Task API reads this at startup and uses it for all processor calls.
  value = "http://processor.${local.name_prefix}.local:8001"
}
