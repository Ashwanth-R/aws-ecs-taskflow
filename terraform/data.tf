# Discover the two AZs to use so we never hard-code us-east-1a/1b.
data "aws_availability_zones" "available" {
  state = "available"
}

# Exposes the current AWS account ID without hard-coding it.
# Used to build IAM policy ARNs.
data "aws_caller_identity" "current" {}
