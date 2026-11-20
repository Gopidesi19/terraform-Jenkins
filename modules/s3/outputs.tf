output "bucket_names" {
  value = { for name, bucket in aws_s3_bucket.this : name => bucket.id }
}
