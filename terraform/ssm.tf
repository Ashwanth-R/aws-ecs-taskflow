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

# processor_base_url SSM parameter removed — Service Connect injects
# the sidecar proxy, so "http://processor:8001" resolves inside the task
# network automatically. No SSM parameter or DNS lookup needed.
