locals {
  name = "${var.project_name}-${var.environment}"
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${local.name}-db-subnet-group"
  })
}

# RDS must only be reachable from the ECS/Fargate security group(s) passed in.
# No ingress from 0.0.0.0/0 anywhere in this resource.
resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "Allow DB traffic only from ECS/Fargate tasks"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow DB access from ECS/Fargate security groups"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name}-rds-sg"
  })
}

resource "aws_db_instance" "this" {
  identifier     = "${local.name}-db"
  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = var.db_port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # RDS is private: never publicly reachable regardless of environment.
  publicly_accessible = false

  backup_retention_period = var.backup_retention_period
  deletion_protection     = var.deletion_protection
  multi_az                = var.multi_az
  skip_final_snapshot     = !var.deletion_protection

  tags = merge(var.tags, {
    Name = "${local.name}-db"
  })
}