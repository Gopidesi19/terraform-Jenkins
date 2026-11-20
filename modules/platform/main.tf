data "aws_ssm_parameter" "amazon_linux_2023" {
  count = var.ami_id == null ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  resolved_ami_id = var.ami_id != null ? var.ami_id : data.aws_ssm_parameter.amazon_linux_2023[0].value
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
  })
  ingress_rules = concat(
    length(var.allowed_ssh_cidrs) == 0 ? [] : [{
      description = "SSH from approved CIDRs"
      protocol    = "tcp"
      from_port   = 22
      to_port     = 22
      cidr_blocks = var.allowed_ssh_cidrs
    }],
    length(var.allowed_http_cidrs) == 0 ? [] : [{
      description = "HTTP from approved CIDRs"
      protocol    = "tcp"
      from_port   = 80
      to_port     = 80
      cidr_blocks = var.allowed_http_cidrs
    }],
    length(var.allowed_https_cidrs) == 0 ? [] : [{
      description = "HTTPS from approved CIDRs"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_blocks = var.allowed_https_cidrs
    }]
  )
}

module "vpc" {
  source = "../vpc"

  project_name      = var.project_name
  environment       = var.environment
  vpc_cidr          = var.vpc_cidr
  subnet_cidr       = var.subnet_cidr
  availability_zone = var.availability_zone
  tags              = local.common_tags
}

module "security_group" {
  source = "../security-group"

  project_name  = var.project_name
  environment   = var.environment
  vpc_id        = module.vpc.vpc_id
  ingress_rules = local.ingress_rules
  tags          = local.common_tags
}

module "ec2" {
  source = "../ec2"

  project_name      = var.project_name
  environment       = var.environment
  instance_count    = 2
  ami_id            = local.resolved_ami_id
  instance_type     = var.instance_type
  key_pair_name     = var.key_pair_name
  subnet_id         = module.vpc.subnet_id
  security_group_id = module.security_group.security_group_id
  tags              = local.common_tags
}

module "s3" {
  source = "../s3"

  project_name    = var.project_name
  environment     = var.environment
  bucket_prefixes = var.bucket_prefixes
  expiration_days = var.s3_expiration_days
  tags            = local.common_tags
}
