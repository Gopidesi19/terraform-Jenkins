variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "instance_count" {
  type    = number
  default = 2

  validation {
    condition     = var.instance_count == 2
    error_message = "This project is configured to create exactly two EC2 instances."
  }
}

variable "ami_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "key_pair_name" {
  type    = string
  default = null
}

variable "subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "root_volume_size" {
  type    = number
  default = 20
}

variable "tags" {
  type    = map(string)
  default = {}
}
