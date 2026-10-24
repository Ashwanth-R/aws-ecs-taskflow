# CloudWatch log groups for both services.
# ECS streams container stdout/stderr here automatically via the awslogs driver.
# 7-day retention keeps costs low for a learning project.

resource "aws_cloudwatch_log_group" "task_api" {
  name              = "/ecs/${local.name_prefix}/task-api"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "job_processor" {
  name              = "/ecs/${local.name_prefix}/job-processor"
  retention_in_days = 7
}
