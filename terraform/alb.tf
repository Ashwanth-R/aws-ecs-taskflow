# Application Load Balancer — the only resource with a public IP.
# It sits in the public subnets and forwards traffic to Task API tasks
# in the private subnets. ECS tasks have private IPs only.
#
# COST: ~$0.025/hour base + ~$0.008/LCU-hour (~$18-25/month).
# To eliminate cost between sessions: terraform destroy -target=aws_lb.main
# The DNS name will change on recreate, but that is fine for a learning env.
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

# Target group — the ALB uses this to track healthy Task API tasks.
# target_type = "ip" is required for Fargate (awsvpc network mode).
resource "aws_lb_target_group" "task_api" {
  name        = "${local.name_prefix}-task-api-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}

# HTTP listener on port 80.
# For production you would add an HTTPS listener on port 443 with an ACM
# certificate and redirect port 80 to 443. Skipped here to keep the
# learning focus on ECS rather than certificate management.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.task_api.arn
  }
}
