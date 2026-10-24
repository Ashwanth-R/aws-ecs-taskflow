# VPC — the private network that contains every resource.
# enable_dns_hostnames is required for Cloud Map private DNS to resolve.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

# ── Public subnets ────────────────────────────────────────────────────────────
# The ALB and NAT Gateway live here. These subnets have a route to the IGW.

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = { Name = "${local.name_prefix}-public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = { Name = "${local.name_prefix}-public-b" }
}

# ── Private subnets ───────────────────────────────────────────────────────────
# ECS tasks and RDS live here. No public IPs, no direct internet access.
# Outbound internet (ECR pulls, CloudWatch, URL checks) goes through the NAT GW.

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = { Name = "${local.name_prefix}-private-a" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = { Name = "${local.name_prefix}-private-b" }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────
# The IGW is the two-way door for the public subnets: inbound from the internet
# reaches the ALB, and outbound from the NAT GW exits here.

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

# ── NAT Gateway ───────────────────────────────────────────────────────────────
# ONE-WAY DOOR: private resources can initiate outbound connections;
# nothing on the internet can initiate inbound connections back through it.
#
# COST WARNING: ~$32/month ($1.08/day) even with zero traffic.
# Delete at the end of each learning session:
#   terraform destroy -target=aws_nat_gateway.main -target=aws_eip.nat
# Recreate when you resume:
#   terraform apply -target=aws_eip.nat -target=aws_nat_gateway.main

resource "aws_eip" "nat" {
  domain     = "vpc"
  tags       = { Name = "${local.name_prefix}-nat-eip" }
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
  tags          = { Name = "${local.name_prefix}-nat" }
  depends_on    = [aws_internet_gateway.main]
}

# ── Route tables ──────────────────────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-public-rt" }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-private-rt" }

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}
