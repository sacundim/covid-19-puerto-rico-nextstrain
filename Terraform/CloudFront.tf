data "aws_cloudfront_distribution" "s3_distribution" {
  id = var.cloudfront_distribution_id
}
