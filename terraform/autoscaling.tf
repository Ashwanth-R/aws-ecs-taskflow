# ── Task API autoscaling ──────────────────────────────────────────────────────

# Register the Task API ECS service as a scalable target.
# min = 1 keeps one task always running; max = 4 caps cost.
resource "aws_appautoscaling_target" "task_api" {
  min_capacity       = 1
  max_capacity       = 4
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.task_api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Scale on ALB request count per target — better than CPU for I/O-bound services.
# The Task API spends most of its time waiting on the processor (I/O), so CPU
# stays low even under heavy load. Request count reflects actual traffic pressure.
# Target: 30 requests/second per task — add a task when load exceeds that.
resource "aws_appautoscaling_policy" "task_api_requests" {
  name               = "${local.name_prefix}-task-api-requests"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.task_api.resource_id
  scalable_dimension = aws_appautoscaling_target.task_api.scalable_dimension
  service_namespace  = aws_appautoscaling_target.task_api.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.task_api.arn_suffix}"
    }
    target_value       = 30    # scale out when requests/task/second exceeds 30
    scale_in_cooldown  = 120
    scale_out_cooldown = 60
  }
}

# ── Job Processor autoscaling ─────────────────────────────────────────────────

resource "aws_appautoscaling_target" "job_processor" {
  min_capacity       = 1
  max_capacity       = 4
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.job_processor.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "job_processor_cpu" {
  name               = "${local.name_prefix}-job-processor-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.job_processor.resource_id
  scalable_dimension = aws_appautoscaling_target.job_processor.scalable_dimension
  service_namespace  = aws_appautoscaling_target.job_processor.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60.0
    scale_in_cooldown  = 120
    scale_out_cooldown = 60
  }
}
