output "alb_dns_name" {
  description = "Public DNS name of the ALB"
  value       = aws_lb.this.dns_name
}

output "ecs_service_security_group_id" {
  description = "Security group ID used by ECS/Fargate tasks - pass this to the RDS module"
  value       = aws_security_group.ecs_service.id
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  value = aws_ecs_service.this.name
}
