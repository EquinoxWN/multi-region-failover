variable "name" {
  description = "Prefix for every resource name."
  type        = string
  default     = "mrf"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.name))
    error_message = "name must be 2 to 21 lowercase letters, digits or dashes, starting with a letter."
  }
}

variable "primary_region" {
  description = "Region that serves traffic and takes writes."
  type        = string
  default     = "us-east-1"
}

variable "standby_region" {
  description = "Region that holds the warm standby."
  type        = string
  default     = "us-west-2"
  validation {
    condition     = var.standby_region != var.primary_region
    error_message = "The standby must be in a different region from the primary."
  }
}

variable "app_image" {
  description = "Container image of the API, pinned by digest (repository@sha256:...)."
  type        = string
  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.app_image))
    error_message = "app_image must be pinned by digest, so both regions run exactly the same build."
  }
}

variable "certificate_arns" {
  description = "ACM certificate for the HTTPS listener in each region (primary and standby)."
  type        = object({ primary = string, standby = string })
}

variable "db_engine_version" {
  description = "Aurora PostgreSQL version; the global database requires the same version in both regions."
  type        = string
  default     = "16.6"
}

variable "primary" {
  description = "Size of the primary stack."
  type = object({
    vpc_cidr          = string
    app_desired_count = number
    app_cpu           = number
    app_memory        = number
    db_instance_class = string
    db_instance_count = number
  })
  default = {
    vpc_cidr          = "10.10.0.0/16"
    app_desired_count = 3
    app_cpu           = 512
    app_memory        = 1024
    db_instance_class = "db.r6g.large"
    db_instance_count = 2
  }
}

variable "standby" {
  description = "Size of the warm standby: running, but at minimal capacity until a failover scales it."
  type = object({
    vpc_cidr          = string
    app_desired_count = number
    app_cpu           = number
    app_memory        = number
    db_instance_class = string
    db_instance_count = number
  })
  default = {
    vpc_cidr          = "10.20.0.0/16"
    app_desired_count = 1
    app_cpu           = 512
    app_memory        = 1024
    db_instance_class = "db.r6g.large"
    db_instance_count = 1
  }
  validation {
    condition     = var.standby.app_desired_count >= 1 && var.standby.db_instance_count >= 1
    error_message = "A warm standby keeps at least one task and one database instance running (zero would be pilot light)."
  }
  validation {
    condition     = var.standby.app_desired_count <= var.primary.app_desired_count && var.standby.db_instance_count <= var.primary.db_instance_count
    error_message = "The standby must not be larger than the primary."
  }
  validation {
    condition     = var.standby.vpc_cidr != var.primary.vpc_cidr
    error_message = "Use different VPC ranges so the regions can be peered later."
  }
}
