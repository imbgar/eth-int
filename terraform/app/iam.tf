resource "aws_iam_role" "task_execution" {
  name = "${var.service_name}-task-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_exec_attach" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_caller_identity" "current" {}

# Grant the execution role permission to read the specific SSM parameter used as a secret
resource "aws_iam_policy" "ssm_read_infura" {
  name        = "${var.service_name}-ssm-read-infura"
  description = "Allow ECS execution role to read INFURA_PROJECT_ID from SSM Parameter Store"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect: "Allow",
        Action: [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ],
        Resource: "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.infura_ssm_parameter_name}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_read_attach" {
  role       = aws_iam_role.task_execution.name
  policy_arn = aws_iam_policy.ssm_read_infura.arn
}
