# ── Execution role ────────────────────────────────────────────────────────────
# Used by the ECS agent (not your app code) to:
#   - Pull container images from ECR
#   - Push logs to CloudWatch Logs
#   - Fetch SSM parameters to inject as env vars at task launch
#
# Your application code never uses this role. It is an AWS infrastructure concern.

resource "aws_iam_role" "execution_role" {
  name = "${local.name_prefix}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# AWS-managed policy: ECR pull (GetAuthorizationToken, BatchGetImage, etc.)
# plus CloudWatch Logs CreateLogStream and PutLogEvents.
resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Extra: read SSM SecureString parameters so ECS can inject DATABASE_URL
# and PROCESSOR_BASE_URL into the container as environment variables.
resource "aws_iam_role_policy" "execution_ssm" {
  name = "ssm-read"
  role = aws_iam_role.execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadSSMSecrets"
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ]
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${local.name_prefix}/*"
    }]
  })
}

# ── Task API task role ────────────────────────────────────────────────────────
# Assumed by the Task API container at runtime (your application code).
# Currently only needs SSM read — the same parameters ECS already injected,
# but accessible via the AWS SDK if the app ever queries SSM directly.
#
# Keep this role separate from the execution role — they serve different
# principals and should carry only what that principal actually needs.

resource "aws_iam_role" "task_api_task_role" {
  name = "${local.name_prefix}-task-api-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "task_api_ssm" {
  name = "ssm-read"
  role = aws_iam_role.task_api_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadSSMParameters"
      Effect = "Allow"
      Action = ["ssm:GetParameter", "ssm:GetParameters"]
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${local.name_prefix}/*"
    }]
  })
}

# Job Processor has no task role — it calls no AWS APIs at runtime.
# Omitting task_role_arn from its task definition is intentional.
