output "state_bucket_name" {
  value = aws_s3_bucket.terraform_state.id
}

output "environment_state_policy_arns" {
  description = "Attach only the matching policy to each environment's Jenkins deployment role."
  value       = { for environment, policy in aws_iam_policy.environment_state_access : environment => policy.arn }
}
