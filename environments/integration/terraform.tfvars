project_name        = "terraform-jenkins"
aws_region          = "us-east-1"
vpc_cidr            = "10.20.0.0/16"
subnet_cidr         = "10.20.1.0/24"
availability_zone   = null
ami_id              = null
instance_type       = "t3.small"
key_pair_name       = null
allowed_ssh_cidrs   = []
allowed_http_cidrs  = []
allowed_https_cidrs = []
bucket_prefixes = {
  artifacts = "tfj-integration-artifacts"
  logs      = "tfj-integration-logs"
}
tags = {
  Owner      = "platform-team"
  CostCenter = "integration"
}
