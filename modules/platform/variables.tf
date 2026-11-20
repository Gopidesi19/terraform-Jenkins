variable "project_name" {
  type = string
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "integration", "pre", "prod"], var.environment)
    error_message = "environment must be dev, integration, pre, or prod."
  }
}

variable "vpc_cidr" {
  type = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "subnet_cidr" {
  type = string

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "availability_zone" {
  type    = string
  default = null
}

variable "ami_id" {
  type        = string
  default     = null
  description = "Optional pinned AMI ID. When null, the latest Amazon Linux 2023 x86_64 AMI is resolved from AWS SSM."
}

variable "instance_type" {
  type = string
}

variable "key_pair_name" {
  type    = string
  default = null
}

variable "allowed_ssh_cidrs" {
  type    = list(string)
  default = []
}

variable "allowed_http_cidrs" {
  type    = list(string)
  default = []
}

variable "allowed_https_cidrs" {
  type    = list(string)
  default = []
}

variable "bucket_prefixes" {
  type = map(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "s3_expiration_days" {
  type    = number
  default = 365
}
