output "alb_dns_name" {
  description = "Public URL for the Task API — curl http://<value>/health"
  value       = aws_lb.main.dns_name
}

output "task_api_ecr_url" {
  description = "ECR URL for Task API — use this in docker push commands"
  value       = aws_ecr_repository.task_api.repository_url
}

output "job_processor_ecr_url" {
  description = "ECR URL for Job Processor — use this in docker push commands"
  value       = aws_ecr_repository.job_processor.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name — use in aws ecs commands"
  value       = aws_ecs_cluster.main.name
}

output "cloudmap_namespace" {
  description = "Private DNS namespace used by Service Connect"
  value       = aws_service_discovery_private_dns_namespace.main.name
}

output "processor_service_connect_name" {
  description = "Name the Task API uses to reach the processor via Service Connect sidecar"
  value       = "processor:8001"
}

output "rds_endpoint" {
  description = "RDS host — only reachable from within the VPC private subnets"
  value       = aws_db_instance.postgres.address
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID — useful for debugging security group and subnet configs"
  value       = aws_vpc.main.id
}
