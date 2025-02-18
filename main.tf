# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "${var.app_name}-vpc"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  availability_zones = data.aws_availability_zones.available.names
}
resource "aws_subnet" "main" {
  count             = var.subnet_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = element(local.availability_zones, count.index)

  tags = {
    Name = "${var.app_name}-subnet-${count.index}"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.app_name}-igw"
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.app_name}-rt"
  }
}

resource "aws_route_table_association" "main" {
  count          = var.subnet_count
  subnet_id      = aws_subnet.main[count.index].id
  route_table_id = aws_route_table.main.id
}

resource "aws_security_group" "main" {
  name   = "${var.app_name}-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "Allow inbound traffic on port ${var.APP_PORT}"
    cidr_blocks = concat(var.allowed_ingress_cidr_blocks, [for eip in aws_eip.nlb : "${eip.public_ip}/32"])
    protocol    = "tcp"
    from_port   = var.APP_PORT
    to_port     = var.APP_PORT
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.allowed_egress_cidr_blocks
  }

  tags = {
    Name = "${var.app_name}-sg"
  }
}

# KMS and Secrets Manager
resource "aws_kms_key" "main" {
  description             = "KMS key for encoding environment variables in the ${var.app_name} application"
  deletion_window_in_days = 10

  tags = {
    Name = "${var.app_name}-kms-key"
  }
}

resource "random_string" "suffix" {
  length  = 5
  special = false
}

resource "aws_secretsmanager_secret" "app_secrets" {
  name       = "${var.app_name}-env-secrets-${random_string.suffix.result}"
  kms_key_id = aws_kms_key.main.arn

  tags = {
    Name = "${var.app_name}-secrets"
  }
}

resource "aws_secretsmanager_secret_version" "app_secrets_version" {
  secret_id = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    PORT                 = var.APP_PORT,
    DB_PROTOCOL          = var.DB_PROTOCOL,
    DB_READONLY_USERNAME = var.DB_READONLY_USERNAME,
    DB_READONLY_SEC      = var.DB_READONLY_SEC,
    DB_HOST              = var.DB_HOST,
    FRONTEND_URL         = var.FRONTEND_URL
  })
}

# IAM Roles and Policies
resource "aws_iam_policy" "ecs_task_kms_secret_manager_policy" {
  name        = "${var.app_name}-ecs-task-kms-secret-manager-policy"
  description = "Policy for ECS task to use KMS key to decrypt SSM parameter"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
          "secretsmanager:GetSecretValue",
          "ec2:AllocateAddress",
          "ec2:ReleaseAddress",
          "ec2:DescribeAddresses",
          "ec2:DisassociateAddress",
          "ec2:AssociateAddress",
          "ec2:DescribeNetworkInterfaces",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ],
        Resource = [
          aws_secretsmanager_secret.app_secrets.arn,
          aws_kms_key.main.arn,
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:elastic-ip/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:network-interface/*",
          "*"
        ]
      }
    ]
  })

  tags = {
    "Name" = "${var.app_name}-kms-secret-manager-policy"
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = { Service = "ecs-tasks.amazonaws.com" }
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
  ]

  tags = {
    Name = "${var.app_name}-ecs-task-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_task_kms_secret_manager_policy.arn
}

# Create CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.app_name}"
  retention_in_days = 30

  tags = {
    Name = "${var.app_name}-cloudwatch-logs"
  }

  depends_on = [
    aws_vpc_endpoint.logs
  ]
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_security_group.main.id]
  subnet_ids         = aws_subnet.main[*].id

  tags = {
    Name = "${var.app_name}-logs-endpoint"
  }
}

# ECS Cluster and Task Definition
resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-cluster"

  tags = {
    Name = "${var.app_name}-cluster"
  }
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
      name      = "${var.app_name}-container",
      image     = var.app_image,
      cpu       = 256,
      memory    = 512,
      essential = true,
      portMappings = [
        {
          containerPort = var.APP_PORT,
          hostPort      = var.APP_PORT
        }
      ],
      secrets = [
        { name = "PORT", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:PORT::" },
        { name = "DB_PROTOCOL", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:DB_PROTOCOL::" },
        { name = "DB_READONLY_USERNAME", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:DB_READONLY_USERNAME::" },
        { name = "DB_READONLY_SEC", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:DB_READONLY_SEC::" },
        { name = "DB_HOST", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:DB_HOST::" },
        { name = "FRONTEND_URL", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:FRONTEND_URL::" }
      ],
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name,
          "awslogs-region"        = var.aws_region,
          "awslogs-stream-prefix" = "ecs"
        }
      },
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.APP_PORT}${var.app_health} || exit 1"],
        interval    = var.health_check_interval,
        timeout     = var.health_check_timeout,
        retries     = var.health_check_unhealthy_threshold,
        startPeriod = 120
      }
    }
  ])

  tags = {
    Name = "${var.app_name}-task"
  }

  depends_on = [aws_cloudwatch_log_group.ecs]
}

resource "aws_ecs_service" "main" {
  name            = "${var.app_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_task_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.main[*].id
    security_groups  = [aws_security_group.main.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs.arn
    container_name   = "${var.app_name}-container"
    container_port   = var.APP_PORT
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.main.arn
  }

  service_registries {
    registry_arn = aws_service_discovery_service.main.arn
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  health_check_grace_period_seconds  = 60

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = []
  }

  tags = {
    Name = "${var.app_name}-service"
  }

  depends_on = [
    aws_lb.nlb,
    aws_lb_target_group.ecs,
    aws_service_discovery_service.main
  ]
}

# Load Balancer and Target Group
resource "aws_eip" "nlb" {
  count      = var.subnet_count
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.app_name}-eip-${count.index}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "nlb" {
  name               = "${var.app_name}-nlb"
  internal           = false
  load_balancer_type = "network"

  dynamic "subnet_mapping" {
    for_each = range(var.subnet_count)
    content {
      subnet_id     = aws_subnet.main[subnet_mapping.key].id
      allocation_id = aws_eip.nlb[subnet_mapping.key].id
    }
  }

  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = var.enable_deletion_protection

  tags = {
    Name = "${var.app_name}-nlb"
  }

  depends_on = [aws_eip.nlb]
}

resource "aws_lb_target_group" "ecs" {
  name        = "${var.app_name}-tg"
  port        = var.APP_PORT
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.app_health
    port                = var.APP_PORT
    protocol            = "HTTP"
    matcher             = "200"
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
  }

  stickiness {
    enabled = true
    type    = "source_ip"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.app_name}-tg"
  }

  depends_on = [aws_lb.nlb]
}

resource "aws_lb_listener" "ecs" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = var.APP_PORT
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs.arn
  }

  tags = {
    "Name" = "${var.app_name}-lb-listener"
  }
  depends_on = [aws_lb_target_group.ecs]
}

# VPC Endpoints
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_security_group.main.id]
  subnet_ids         = aws_subnet.main[*].id

  tags = {
    Name = "${var.app_name}-secretsmanager-endpoint"
  }
}

resource "aws_vpc_endpoint" "kms" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.${var.aws_region}.kms"
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_security_group.main.id]
  subnet_ids         = aws_subnet.main[*].id

  tags = {
    Name = "${var.app_name}-kms-endpoint"
  }
}

# Add Service Discovery
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "${var.app_name}.local"
  description = "Service discovery namespace for ${var.app_name}"
  vpc         = aws_vpc.main.id

  tags = {
    Name = "${var.app_name}-dns-namespace"
  }
}

resource "aws_service_discovery_service" "main" {
  name = var.app_name

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = {
    Name = "${var.app_name}-discovery-service"
  }

  depends_on = [aws_service_discovery_private_dns_namespace.main]
}
# Add Application Auto Scaling
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = var.max_task_count
  min_capacity       = var.min_task_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  tags = {
    "Name" = "${var.app_name}-scaling-target"
  }
}

# CPU Utilization Scaling
resource "aws_appautoscaling_policy" "cpu_scaling" {
  name               = "${var.app_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = var.target_cpu_utilization

    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# Memory Utilization Scaling
resource "aws_appautoscaling_policy" "memory_scaling" {
  name               = "${var.app_name}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value = var.target_memory_utilization

    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# Outputs
output "service_url" {
  value       = "http://${aws_lb.nlb.dns_name}:${var.APP_PORT}"
  description = "The URL of the service"
}

output "public_ips" {
  value       = aws_eip.nlb[*].public_ip
  description = "The public IPs of the Elastic IPs"
}

output "public_dns" {
  value       = aws_eip.nlb[*].public_dns
  description = "The public DNS of the Elastic IPs"
}

output "service_discovery_endpoint" {
  value       = "${var.app_name}.${aws_service_discovery_private_dns_namespace.main.name}"
  description = "The service discovery endpoint"
}
