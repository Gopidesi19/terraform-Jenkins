variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "bucket_prefixes" {
  type = map(string)

  validation {
    condition     = length(var.bucket_prefixes) == 2
    error_message = "Provide exactly two bucket prefixes."
  }
}

variable "expiration_days" {
  type    = number
  default = 365
}

variable "noncurrent_version_expiration_days" {
  type    = number
  default = 90
}

variable "tags" {
  type    = map(string)
  default = {}
}
