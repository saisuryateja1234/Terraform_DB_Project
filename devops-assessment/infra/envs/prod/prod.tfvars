aws_region   = "us-east-1"
project_name = "hotelbook"
environment  = "prod"

desired_count = 2
task_cpu      = "512"
task_memory   = "1024"

db_instance_class          = "db.t3.medium"
db_allocated_storage       = 100
db_backup_retention_period = 30
db_deletion_protection     = true
db_multi_az                = true
