output "vpc_id" {
  value = module.vpc.vpc_id
}

output "subnet_id" {
  value = module.vpc.subnet_id
}

output "instance_ids" {
  value = module.ec2.instance_ids
}

output "instance_public_ips" {
  value = module.ec2.public_ips
}

output "security_group_id" {
  value = module.security_group.security_group_id
}

output "bucket_names" {
  value = module.s3.bucket_names
}
