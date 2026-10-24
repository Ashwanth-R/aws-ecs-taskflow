# Cloud Map private DNS namespace.
# This creates a Route 53 private hosted zone visible only within this VPC.
# Any resource in the VPC can resolve names like processor.taskflow.local.
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "${local.name_prefix}.local"
  description = "Private service discovery for TaskFlow"
  vpc         = aws_vpc.main.id
}

# aws_service_discovery_service removed — Service Connect manages its own
# service registrations automatically. The namespace above is still required;
# Service Connect uses it to scope service names within the VPC.
