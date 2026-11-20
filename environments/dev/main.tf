module "platform" {
  source = "../../modules/platform"

  project_name        = var.project_name
  environment         = "dev"
  vpc_cidr            = var.vpc_cidr
  subnet_cidr         = var.subnet_cidr
  availability_zone   = var.availability_zone
  ami_id              = var.ami_id
  instance_type       = var.instance_type
  key_pair_name       = var.key_pair_name
  allowed_ssh_cidrs   = var.allowed_ssh_cidrs
  allowed_http_cidrs  = var.allowed_http_cidrs
  allowed_https_cidrs = var.allowed_https_cidrs
  bucket_prefixes     = var.bucket_prefixes
  tags                = var.tags
}
