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