output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.alb.dns_name
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.this.arn
}

output "tiles_service_arn" {
  description = "ARN of the tiles ECS service"
  value       = aws_ecs_service.tiles.arn
}

output "timeseries_service_arn" {
  description = "ARN of the timeseries ECS service"
  value       = aws_ecs_service.timeseries.arn
}

output "tiles_service_name" {
  description = "Name of the tiles ECS service"
  value       = aws_ecs_service.tiles.name
}

output "timeseries_service_name" {
  description = "Name of the timeseries ECS service"
  value       = aws_ecs_service.timeseries.name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.alb.arn
}
