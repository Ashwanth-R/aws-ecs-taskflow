# Security groups reference each other as sources instead of IP ranges.
# When a new ECS task starts with a new private IP, any rule that says
# "from task-api-sg" automatically covers it — no IP list to update.
#
# We define all four groups first (no rules), then add rules as separate
# resources. This avoids the Terraform circular-dependency error that
# occurs when group A's egress rule references group B while group B's
# ingress rule references group A.

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB: public HTTP in, Task API out"
  vpc_id      = aws_vpc.main.id
  lifecycle { create_before_destroy = true }
}

resource "aws_security_group" "task_api" {
  name        = "${local.name_prefix}-task-api-sg"
  description = "Task API: ALB in; processor, db, and internet out"
  vpc_id      = aws_vpc.main.id
  lifecycle { create_before_destroy = true }
}

resource "aws_security_group" "processor" {
  name        = "${local.name_prefix}-processor-sg"
  description = "Processor: Task API in only; ECR and URL checks out"
  vpc_id      = aws_vpc.main.id
  lifecycle { create_before_destroy = true }
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS: Task API in only"
  vpc_id      = aws_vpc.main.id
  lifecycle { create_before_destroy = true }
}

# ── ALB rules ─────────────────────────────────────────────────────────────────

resource "aws_security_group_rule" "alb_ingress_http" {
  security_group_id = aws_security_group.alb.id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Public HTTP"
}

resource "aws_security_group_rule" "alb_egress_task_api" {
  security_group_id        = aws_security_group.alb.id
  type                     = "egress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.task_api.id
  description              = "Forward to Task API"
}

# ── Task API rules ────────────────────────────────────────────────────────────

resource "aws_security_group_rule" "task_api_ingress_alb" {
  security_group_id        = aws_security_group.task_api.id
  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  description              = "From ALB only"
}

resource "aws_security_group_rule" "task_api_egress_processor" {
  security_group_id        = aws_security_group.task_api.id
  type                     = "egress"
  from_port                = 8001
  to_port                  = 8001
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.processor.id
  description              = "Call Job Processor"
}

resource "aws_security_group_rule" "task_api_egress_rds" {
  security_group_id        = aws_security_group.task_api.id
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds.id
  description              = "PostgreSQL"
}

resource "aws_security_group_rule" "task_api_egress_https" {
  security_group_id = aws_security_group.task_api.id
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "ECR, SSM, CloudWatch via NAT Gateway"
}

# ── Processor rules ───────────────────────────────────────────────────────────

resource "aws_security_group_rule" "processor_ingress_task_api" {
  security_group_id        = aws_security_group.processor.id
  type                     = "ingress"
  from_port                = 8001
  to_port                  = 8001
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.task_api.id
  description              = "From Task API only - processor has no public access"
}

resource "aws_security_group_rule" "processor_egress_https" {
  security_group_id = aws_security_group.processor.id
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "ECR pulls and HTTPS URL checking via NAT Gateway"
}

resource "aws_security_group_rule" "processor_egress_http" {
  security_group_id = aws_security_group.processor.id
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTP URL checking via NAT Gateway"
}

# ── RDS rules ─────────────────────────────────────────────────────────────────

resource "aws_security_group_rule" "rds_ingress_task_api" {
  security_group_id        = aws_security_group.rds.id
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.task_api.id
  description              = "From Task API only - processor has no database access"
}
