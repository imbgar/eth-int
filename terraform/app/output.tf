output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  value = aws_lb.this.zone_id
}

output "alb_arn" {
  value = aws_lb.this.arn
}

output "alb_target_group_arn" {
  value = aws_lb_target_group.tg.arn
}

output "alb_http_listener_arn" {
  value = aws_lb_listener.http.arn
}

output "health_check_url" {
  value = "http://${aws_lb.this.dns_name}/healthz"
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

output "security_group_alb_id" {
  value = aws_security_group.alb_sg.id
}

output "security_group_service_id" {
  value = aws_security_group.service_sg.id
}

output "ecs_cluster_arn" {
  value = aws_ecs_cluster.this.arn
}

output "ecs_service_arn" {
  value = aws_ecs_service.svc.arn
}

output "ecs_task_definition_arn" {
  value = aws_ecs_task_definition.task.arn
}

output "cloudwatch_log_group_name" {
  value = aws_cloudwatch_log_group.this.name
}

output "task_execution_role_arn" {
  value = aws_iam_role.task_execution.arn
}

output "container_image" {
  value = var.container_image
}

output "infura_ssm_parameter_name" {
  value = var.infura_ssm_parameter_name
}