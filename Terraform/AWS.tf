terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  profile = "admin"
  region  = "us-west-2"
}

data "aws_region" "current" {}
data "aws_availability_zones" "available" {}

# This provider is here only to support AWS Certificate Manager
# ("ACM"), which works onlu in us-east-1
provider "aws" {
  alias = "acm_provider"
  profile = "admin"
  region = "us-east-1"
}