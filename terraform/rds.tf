# RDS subnet group — tells RDS which subnets it can place instances in.
# Both private subnets are included so RDS can span AZs if multi_az is enabled later.
resource "aws_db_subnet_group" "main" {
  name        = "${local.name_prefix}-db-subnet-group"
  description = "Private subnets for RDS"
  subnet_ids  = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

# PostgreSQL instance.
#
# COST: db.t3.micro costs ~$0.017/hour (~$12/month) when running.
# Stop it between learning sessions:
#   aws rds stop-db-instance --db-instance-identifier taskflow-postgres --region us-east-1
# AWS auto-restarts a stopped instance after 7 days — set a calendar reminder.
#
# To destroy completely (loses all data):
#   terraform destroy -target=aws_db_instance.postgres
resource "aws_db_instance" "postgres" {
  identifier        = "${local.name_prefix}-postgres"
  engine            = "postgres"
  engine_version    = "15"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "taskflow"
  username = "taskflow"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false  # Never expose the database to the internet
  multi_az            = false  # Single AZ to save ~$12/month; set true for production
  skip_final_snapshot = true   # Skips snapshot on destroy — fine for learning, not for production

  tags = { Name = "${local.name_prefix}-postgres" }
}
