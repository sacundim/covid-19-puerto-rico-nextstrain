##############################################################################
##############################################################################
##
## IAM permissions that we need to grant to our job containers.
##

resource "aws_iam_role" "ecs_job_role" {
  name = "${var.project_name}-job-role"
  tags = {
    Project = var.project_name
  }

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}


resource "aws_iam_role_policy_attachment" "ecs_job_role_main_bucket" {
  role       = aws_iam_role.ecs_job_role.name
  policy_arn = aws_iam_policy.access_to_main_bucket.arn
}

resource "aws_iam_policy" "access_to_main_bucket" {
  name        = "${var.project_name}-jobs-access-to-main-bucket"
  description = "Access to the the main website bucket."

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "VisualEditor0",
        "Effect": "Allow",
        "Action": [
          "s3:ListBucket"
        ],
        "Resource": [
          "arn:aws:s3:::${var.main_bucket_name}"
        ]
      },
      {
        "Sid": "VisualEditor1",
        "Effect": "Allow",
        "Action": [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:CopyObject"
        ],
        "Resource": [
          "arn:aws:s3:::${var.main_bucket_name}/auspice/*",
          "arn:aws:s3:::${var.main_bucket_name}/auspice"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_job_role_invalidate_cloudfront" {
  role       = aws_iam_role.ecs_job_role.name
  policy_arn = aws_iam_policy.invalidate_cloudfront.arn
}

resource "aws_iam_policy" "invalidate_cloudfront" {
  name        = "${var.project_name}-invalidate-cloudfront"
  description = "Allow creation of a Cloudfront invalidation."

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "VisualEditor0",
        "Effect": "Allow",
        "Action": [
          "cloudfront:CreateInvalidation"
        ],
        "Resource": ["*"]
      }
    ]
  })
}


##############################################################################
##############################################################################
##
## IAM permissions that we need to grant to AWS services (Batch, ECS,
## Cloudwatch).  These are generally formulaic (AWS-managed policies).
##

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-task-role"
  tags = {
    Project = var.project_name
  }

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


resource "aws_iam_role" "batch_service_role" {
  name = "${var.project_name}-batch-service-role"
  tags = {
    Project = var.project_name
  }

  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Effect": "Allow",
        "Principal": {
          "Service": "batch.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "batch_service_role" {
  role       = aws_iam_role.batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}
