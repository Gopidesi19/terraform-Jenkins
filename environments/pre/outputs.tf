output "vpc_id" {
  value = module.platform.vpc_id
}

output "subnet_id" {
  value = module.platform.subnet_id
}

output "instance_ids" {
  value = module.platform.instance_ids
}

output "security_group_id" {
  value = module.platform.security_group_id
}

output "bucket_names" {
  value = module.platform.bucket_names
}
