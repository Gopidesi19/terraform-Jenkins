variable "project_name" {
  type    = string
  default = "terraform-jenkins"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type = string
}

variable "subnet_cidr" {
  type = string
}

variable "availability_zone" {
  type    = string
  default = null
}

variable "ami_id" {
  type    = string
  default = null
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
