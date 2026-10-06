variable "role" {
  description = "primary (serves and writes) or standby (warm, receives replication)."
  type        = string
  validation {
    condition     = contains(["primary", "standby"], var.role)
    error_message = "role must be primary or standby."
  }
}

variable "name" {
  description = "Prefix for resource names in this region."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC address range."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be a valid range of /20 or larger."
  }
}

variable "az_count" {
  description = "Availability zones to spread subnets over."
  type        = number
  default     = 2
  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "Use two or three availability zones."
  }
}

variable "app_image" {
  description = "Container image pinned by digest."
  type        = string
}

variable "app_port" {
  description = "Port the API listens on inside the container."
  type        = number
  default     = 8080
}

variable "app_cpu" {
  description = "Fargate task CPU units."
  type        = number
}

variable "app_memory" {
  description = "Fargate task memory in MiB."
  type        = number
}

variable "app_desired_count" {
  description = "Running API tasks."
  type        = number
}

variable "certificate_arn" {
  description = "ACM certificate for the HTTPS listener."
  type        = string
}

variable "db_engine_version" {
  description = "Aurora PostgreSQL version."
  type        = string
}

variable "db_instance_class" {
  description = "Aurora instance class."
  type        = string
}

variable "db_instance_count" {
  description = "Aurora instances (writer plus readers in the primary; readers in the standby)."
  type        = number
}

variable "global_cluster_id" {
  description = "Aurora global database this regional cluster belongs to."
  type        = string
}

variable "log_retention_days" {
  description = "How long API logs are kept."
  type        = number
  default     = 30
}
