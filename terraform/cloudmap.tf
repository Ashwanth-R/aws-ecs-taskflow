# Cloud Map private DNS namespace.
# This creates a Route 53 private hosted zone visible only within this VPC.
# Any resource in the VPC can resolve names like processor.taskflow.local.
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "${local.name_prefix}.local"
  description = "Private service discovery for TaskFlow"
  vpc         = aws_vpc.main.id
}

# Service registration for the Job Processor.
# When ECS starts a processor task it registers an A record here.
# When the task stops ECS removes the record automatically.
# The Task API calls http://processor.taskflow.local:8001 and gets the
# processor's current private IP without ever knowing what it is.
resource "aws_service_discovery_service" "processor" {
  name = "processor"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.main.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10   # Low TTL so the API picks up a replaced task quickly
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}
