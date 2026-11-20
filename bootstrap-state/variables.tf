variable "project_name" {
  type    = string
  default = "terraform-jenkins"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_prefix" {
  type        = string
  description = "Lowercase globally unique prefix; AWS appends a random suffix to create the state bucket."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{2,35}-$", var.bucket_prefix))
    error_message = "bucket_prefix must be 4-37 lowercase letters, digits, dots, or hyphens and end in a hyphen."
  }
}

variable "state_keys" {
  type = map(string)
  default = {
    dev         = "dev/terraform.tfstate"
    integration = "integration/terraform.tfstate"
    pre         = "pre/terraform.tfstate"
    prod        = "prod/terraform.tfstate"
  }

  validation {
    condition     = length(var.state_keys) == 4 && alltrue([for environment in ["dev", "integration", "pre", "prod"] : contains(keys(var.state_keys), environment)])
    error_message = "state_keys must define exactly dev, integration, pre, and prod."
  }
}
