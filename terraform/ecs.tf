# ── Cluster ───────────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = local.name_prefix

  # Container Insights adds per-container CPU/memory metrics to CloudWatch.
  # Small extra cost (~$0.30/task/month) but very useful while learning.
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# ── Task API task definition ──────────────────────────────────────────────────
# A task definition is a blueprint: it says what container to run, how much
# CPU/memory to give it, which IAM roles to use, and how to handle logs.
# It is versioned — deploying a new image creates a new revision.

resource "aws_ecs_task_definition" "task_api" {
  family                   = "${local.name_prefix}-task-api"
  network_mode             = "awsvpc"          # Required for Fargate; each task gets its own ENI
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"             # 0.25 vCPU
  memory                   = "512"             # 512 MB
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_api_task_role.arn

  container_definitions = jsonencode([{
    name      = "task-api"
    image     = "${aws_ecr_repository.task_api.repository_url}:${var.task_api_image_tag}"
    essential = true

    portMappings = [{
      containerPort = 8000
      protocol      = "tcp"
    }]

    environment = [
      { name = "LOG_LEVEL",                 value = "INFO" },
      { name = "MAX_URLS_PER_JOB",          value = "10" },
      { name = "PROCESSOR_TIMEOUT_SECONDS", value = "10" },
      # Service Connect injects a sidecar proxy that handles routing to "processor".
      # The short name works because the proxy intercepts it inside the task network.
      { name = "PROCESSOR_BASE_URL",        value = "http://processor:8001" }
    ]

    # ECS fetches these SSM parameters at task launch (using the execution role)
    # and injects them as environment variables. The container sees them as
    # ordinary env vars — no SSM SDK calls needed in application code.
    secrets = [
      { name = "DATABASE_URL", valueFrom = aws_ssm_parameter.database_url.arn }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.task_api.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "task-api"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "python3 -c \"import urllib.request; urllib.request.urlopen('http://localhost:8000/health')\" || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])
}

# ── Task API ECS service ──────────────────────────────────────────────────────
# A service keeps the desired number of tasks running and replaces failed ones.
# It also registers/deregisters task IPs with the ALB target group.

resource "aws_ecs_service" "task_api" {
  name            = "task-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.task_api.arn
  desired_count   = var.task_api_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups  = [aws_security_group.task_api.id]
    assign_public_ip = false  # Tasks are private; the ALB is the public entry point
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.task_api.arn
    container_name   = "task-api"
    container_port   = 8000
  }

  # Service Connect — client side only.
  # Enables the sidecar proxy so this task can call "processor:8001".
  # No service{} block here because Task API is not a discovered service itself.
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.main.arn
  }

  # Wait for the listener to exist before registering tasks — avoids a race
  # condition where ECS tries to register targets before the target group is ready.
  depends_on = [aws_lb_listener.http]
}

# ── Job Processor task definition ─────────────────────────────────────────────

resource "aws_ecs_task_definition" "job_processor" {
  family                   = "${local.name_prefix}-job-processor"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution_role.arn
  # No task_role_arn — the processor never calls AWS APIs at runtime

  container_definitions = jsonencode([{
    name      = "job-processor"
    image     = "${aws_ecr_repository.job_processor.repository_url}:${var.job_processor_image_tag}"
    essential = true

    portMappings = [{
      containerPort = 8001
      protocol      = "tcp"
      name          = "processor"   # Service Connect matches this name to the service{} block below
    }]

    environment = [
      { name = "LOG_LEVEL",           value = "INFO" },
      { name = "MAX_URLS_PER_JOB",    value = "10" },
      { name = "URL_TIMEOUT_SECONDS", value = "3" }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.job_processor.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "job-processor"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "python3 -c \"import urllib.request; urllib.request.urlopen('http://localhost:8001/health')\" || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])
}

# ── Job Processor ECS service ─────────────────────────────────────────────────

resource "aws_ecs_service" "job_processor" {
  name            = "job-processor"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.job_processor.arn
  desired_count   = var.job_processor_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups  = [aws_security_group.processor.id]
    assign_public_ip = false
  }

  # Service Connect — server side.
  # Advertises this service as "processor" in the namespace.
  # The sidecar proxy on each task handles inbound routing and health tracking.
  # client_alias defines what callers use: http://processor:8001
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.main.arn

    service {
      port_name      = "processor"   # must match portMappings[].name above
      discovery_name = "processor"

      client_alias {
        port     = 8001
        dns_name = "processor"
      }
    }
  }
}
