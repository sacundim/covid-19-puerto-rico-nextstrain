resource "aws_ecr_repository" "nextstrain_repo" {
  name = var.project_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

data "aws_ecr_image" "nextstrain_job" {
  repository_name = aws_ecr_repository.nextstrain_repo.name
  image_tag       = "latest"
}
