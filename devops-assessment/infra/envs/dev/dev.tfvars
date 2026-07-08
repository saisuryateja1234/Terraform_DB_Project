aws_region   = "us-east-1"
project_name = "hotelbook"
environment  = "dev"

desired_count = 1
task_cpu      = "256"
task_memory   = "512"

db_instance_class          = "db.t3.micro"
db_allocated_storage       = 20
db_backup_retention_period = 3
db_deletion_protection     = false
db_multi_az                = false
