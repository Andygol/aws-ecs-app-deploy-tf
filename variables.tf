# AWS credentials and region
variable "aws_access_key" {
  description = "The IAM public access key"
  type        = string
}

variable "aws_secret_key" {
  description = "IAM secret access key"
  type        = string
}

variable "aws_region" {
  description = "The AWS region things are created in"
  type        = string
}

# Application settings
variable "app_name" {
  description = "The name of the application"
  type        = string
  default     = "my-demo-app"
}

variable "APP_PORT" {
  description = "The port the application listens on"
  default     = 3000
  type        = number
}

variable "DB_PROTOCOL" {
  description = "The protocol to use to connect to the database"
  type        = string
}

variable "DB_READONLY_USERNAME" {
  description = "The username to use to connect to the database"
  type        = string
}

variable "DB_READONLY_SEC" {
  description = "The password to use to connect to the database"
  type        = string
}

variable "DB_HOST" {
  description = "The host to use to connect to the database"
  type        = string
}

variable "FRONTEND_URL" {
  description = "The URL of the frontend application"
  type        = string
}

variable "app_health" {
  description = "The health check path for the application"
  type        = string
  default     = "/health"
}

variable "app_image" {
  description = "The Docker image to use for the application"
  type        = string
}

variable "subnet_count" {
  description = "The number of subnets to create"
  type        = number
  default     = 2
}

variable "desired_task_count" {
  description = "The number of tasks to run in the ECS service"
  type        = number
  default     = 1
}

variable "health_check_interval" {
  description = "Number of seconds between health checks"
  type        = number
  default     = 120
}

variable "health_check_timeout" {
  description = "Number of seconds to wait for a health check response"
  type        = number
  default     = 30
}

variable "health_check_healthy_threshold" {
  description = "Number of consecutive health checks successes required"
  type        = number
  default     = 5
}

variable "health_check_unhealthy_threshold" {
  description = "Number of consecutive health check failures required"
  type        = number
  default     = 5
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}

variable "allowed_ingress_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the application"
  type        = list(string)
  default     = [] # Do not use 0.0.0.0/0 in production
}

variable "allowed_egress_cidr_blocks" {
  description = "List of CIDR blocks allowed for egress traffic"
  type        = list(string)
  default     = [] # Restrict as needed
}

# Autoscaling settings
variable "min_task_count" {
  description = "Minimum number of tasks to run"
  type        = number
  default     = 1
}

variable "max_task_count" {
  description = "Maximum number of tasks to run"
  type        = number
  default     = 10
}

variable "target_cpu_utilization" {
  description = "Target CPU utilization percentage"
  type        = number
  default     = 70
}

variable "target_memory_utilization" {
  description = "Target memory utilization percentage"
  type        = number
  default     = 70
}

variable "scale_in_cooldown" {
  description = "The amount of time, in seconds, after a scale in activity completes before another scale in activity can start"
  type        = number
  default     = 300
}

variable "scale_out_cooldown" {
  description = "The amount of time, in seconds, after a scale out activity completes before another scale out activity can start"
  type        = number
  default     = 300
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "owner" {
  description = "Owner of the resources"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing purposes"
  type        = string
  default     = "undefined"
}
