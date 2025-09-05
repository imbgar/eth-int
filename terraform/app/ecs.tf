resource "aws_ecs_cluster" "this" {
  name = var.service_name
}

resource "aws_ecs_task_definition" "task" {
  family                   = var.service_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.task_execution.arn
  container_definitions = jsonencode([
    {
      name      = var.service_name,
      image     = coalesce(try(data.aws_ssm_parameter.image_digest.value, null), var.container_image),
      essential = true,
      portMappings = [{ containerPort = 3000, hostPort = 3000 }],
      secrets = [{ name = "INFURA_PROJECT_ID", valueFrom = var.infura_ssm_parameter_name }],
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-region        = var.aws_region,
          awslogs-group         = "/ecs/${var.service_name}",
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

resource "aws_ecs_service" "svc" {
  name            = var.service_name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.task.arn
  desired_count   = 2
  launch_type     = "FARGATE"
  network_configuration {
    subnets         = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups = [aws_security_group.service_sg.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = var.service_name
    container_port   = 3000
  }
  depends_on = [aws_lb_listener.http]

  # CI updates the task definition revision; Terraform should not roll it back
  lifecycle {
    ignore_changes = [task_definition]
  }
}