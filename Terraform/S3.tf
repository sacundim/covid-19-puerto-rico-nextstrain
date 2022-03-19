// Website bucket
data "aws_s3_bucket" "main_bucket" {
  bucket = var.main_bucket_name
}

// HTTP access logs bucket
data "aws_s3_bucket" "logs_bucket" {
  bucket = var.logs_bucket_name
}
