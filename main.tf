# Create KMS key
resource "aws_kms_key" "main" {
  description             = "KMS key for encoding environment variables in the ${var.app_name} application"
  deletion_window_in_days = 10

  tags = {
    Name = "${var.app_name}-kms-key"
  }
}

# Prepare the environment variables for the application to store in Secrets Manager
resource "random_string" "suffix" {
  length  = 5
  special = false
}

resource "aws_secretsmanager_secret" "app_secrets" {
  name       = "${var.app_name}-env-secrets-${random_string.suffix.result}"
  kms_key_id = aws_kms_key.main.arn
}

# Encrypted environment variables for the application stored in Secrets Manager
resource "aws_secretsmanager_secret_version" "app_secrets_version" {
  secret_id = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    PORT                 = var.APP_PORT,
    DB_PROTOCOL          = var.DB_PROTOCOL,
    DB_READONLY_USERNAME = var.DB_READONLY_USERNAME,
    DB_READONLY_SEC      = var.DB_READONLY_SEC,
    DB_HOST              = var.DB_HOST
  })
}

# Create the IAM policy for the ECS task to access the KMS key and Secrets Manager
resource "aws_iam_policy" "ecs_task_kms_secret_manager_policy" {
  name        = "${var.app_name}-ecs-task-kms-secret-manager-policy"
  description = "Policy for ECS task to use KMS key to decrypt SSM parameter"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.app_secrets.arn,
          aws_kms_key.main.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_task_kms_secret_manager_policy.arn
}

resource "aws_iam_role" "ecs_task_execution_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
  ]
}

resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-cluster"
}

resource "aws_ecs_task_definition" "main" {
  family                   = "${var.app_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn
  cpu                      = 256
  memory                   = 512

  container_definitions = jsonencode([
    {
      name      = "${var.app_name}-container"
      image     = var.app_image
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = var.APP_PORT
          hostPort      = var.APP_PORT
        }
      ]
      secrets = [
        { name = "PORT", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:PORT::" },
        { name = "DB_PROTOCOL", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:DB_PROTOCOL::" },
        { name = "DB_READONLY_USERNAME", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:DB_READONLY_USERNAME::" },
        { name = "DB_READONLY_SEC", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:DB_READONLY_SEC::" },
        { name = "DB_HOST", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:DB_HOST::" }
      ]
    }
  ])
}

resource "aws_ecs_service" "main" {
  name            = "${var.app_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.id
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.main[*].id
    security_groups  = [aws_security_group.main.id]
    assign_public_ip = true
  }
}

resource "aws_security_group" "main" {
  name   = "${var.app_name}-security-group"
  vpc_id = aws_vpc.main.id

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "tcp"
    from_port   = var.APP_PORT
    to_port     = var.APP_PORT
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "${var.app_name}-vpc"
  }
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "main" {
  count             = 1
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "${var.app_name}-subnet-${count.index}"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "main" {
  count          = 1
  subnet_id      = aws_subnet.main[count.index].id
  route_table_id = aws_route_table.main.id
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type = "Interface"

  security_group_ids = [aws_security_group.main.id]
  subnet_ids         = aws_subnet.main[*].id
}

resource "aws_vpc_endpoint" "kms" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.kms"
  vpc_endpoint_type = "Interface"

  security_group_ids = [aws_security_group.main.id]
  subnet_ids         = aws_subnet.main[*].id
}

