/********************************************
 * S3 buckets
 */

resource "aws_s3_bucket" "jobs_bucket" {
  bucket = var.jobs_bucket_name

  tags = {
    Project = var.project_name
  }

  lifecycle_rule {
    id      = "Tiered storage"
    enabled = true

    transition {
      days          = 31
      storage_class = "INTELLIGENT_TIERING"
    }

    abort_incomplete_multipart_upload_days = 7
  }
}

resource "aws_s3_bucket_public_access_block" "block_jobs_bucket" {
  bucket = aws_s3_bucket.jobs_bucket.id
  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}


/********************************************
 * Cloudwatch logging
 */

resource "aws_cloudwatch_log_group" "log_group" {
  name = var.project_name
  retention_in_days = 30
  tags = {
    Project = var.project_name
  }
}


/********************************************
 * IAM
 */

resource "aws_iam_policy" "access_to_batch" {
  name        = "${var.project_name}-jobs-access-to-batch"
  description = "Grant Nextstrain CLI access to AWS Batch."

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "VisualEditor0",
        "Effect": "Allow",
        "Action": [
          "batch:DescribeJobQueues",
          "batch:TerminateJob",
          "batch:DescribeJobs",
          "batch:CancelJob",
          "batch:SubmitJob",
          "batch:DescribeJobDefinitions",
          "batch:RegisterJobDefinition"
        ],
        "Resource": "*"
      },
      {
        "Sid": "VisualEditor1",
        "Effect": "Allow",
        "Action": "iam:PassRole",
        "Resource": "arn:aws:iam::*:role/NextstrainJobsRole"
      }
    ]
  })
}

resource "aws_iam_policy" "access_to_bucket" {
  name        = "${var.project_name}-jobs-access-to-bucket"
  description = "Grant Nextstrain CLI access to the S3 jobs bucket."

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "VisualEditor0",
        "Effect": "Allow",
        "Action": [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ],
        "Resource": [
          "arn:aws:s3:::${var.jobs_bucket_name}/*",
          "arn:aws:s3:::${var.jobs_bucket_name}"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "access_to_logs" {
  name        = "${var.project_name}-jobs-access-to-logs"
  description = "Grant Nextstrain CLI access to AWS logging."

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "VisualEditor0",
        "Effect": "Allow",
        "Action": [
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:DeleteLogStream"
        ],
        "Resource": [
          "arn:aws:logs:*:*:log-group:${aws_cloudwatch_log_group.log_group.name}",
          "arn:aws:logs:*:*:log-group:${aws_cloudwatch_log_group.log_group.name}:log-stream:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-jobs-role"
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

resource "aws_iam_role_policy_attachment" "ecs_task_role" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.access_to_bucket.arn
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


resource "aws_iam_group" "nextstrain_jobs" {
  name = "nextstrain-jobs"
  path = "/"
}

resource "aws_iam_group_policy_attachment" "access_to_batch" {
  group      = aws_iam_group.nextstrain_jobs.name
  policy_arn = aws_iam_policy.access_to_batch.arn
}

resource "aws_iam_group_policy_attachment" "access_to_bucket" {
  group      = aws_iam_group.nextstrain_jobs.name
  policy_arn = aws_iam_policy.access_to_bucket.arn
}

resource "aws_iam_group_policy_attachment" "access_to_logs" {
  group      = aws_iam_group.nextstrain_jobs.name
  policy_arn = aws_iam_policy.access_to_logs.arn
}

data "aws_iam_user" "user" {
  user_name = var.iam_user
}

resource "aws_iam_user_group_membership" "user_nextstrain_member" {
  user = data.aws_iam_user.user.user_name
  groups = [
    aws_iam_group.nextstrain_jobs.name
  ]
}

/********************************************
 * Batch
 */

resource "aws_batch_job_definition" "nextstrain_job" {
  name = "nextstrain-job"
  tags = {
    Project = var.project_name
  }
  type = "container"
  platform_capabilities = ["FARGATE"]

  container_properties = jsonencode({
    image = "nextstrain/base:latest"
    executionRoleArn = aws_iam_role.ecs_task_role.arn
    fargatePlatformConfiguration = {
      "platformVersion": "LATEST"
    },
    resourceRequirements = [
      {"type": "VCPU", "value": "4"},
      {"type": "MEMORY", "value": "8192"}
    ]
  })

  retry_strategy {
    attempts = 1
  }

  timeout {
    attempt_duration_seconds = 14440
  }
}

resource "aws_batch_compute_environment" "nextstrain" {
  compute_environment_name = "${var.project_name}-compute-environment"
  tags = {
    Project = var.project_name
  }

  compute_resources {
    max_vcpus = 16

    security_group_ids = [
      aws_security_group.outbound_only.id
    ]

    subnets = aws_subnet.subnet.*.id

    type = "FARGATE"
  }

  service_role = aws_iam_role.batch_service_role.arn
  type         = "MANAGED"
  depends_on   = [aws_iam_role_policy_attachment.batch_service_role]
}


resource "aws_batch_job_queue" "nextstrain-queue" {
  name     = "nextstrain-job-queue"
  tags = {
    Project = var.project_name
  }
  state    = "ENABLED"
  priority = 1
  compute_environments = [
    aws_batch_compute_environment.nextstrain.arn
  ]
}


/********************************************
 * VPC
 */

resource "aws_vpc" "main" {
  cidr_block = var.cidr_block
  tags = {
    Name = var.project_name
    Project = var.project_name
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Project = var.project_name
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Project = var.project_name
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_subnet" "subnet" {
  vpc_id     = aws_vpc.main.id
  count = var.az_count
  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block  = cidrsubnet(aws_vpc.main.cidr_block, 2, count.index)
  #  cidr_block = "172.32.0.0/20"
  map_public_ip_on_launch = true
  tags = {
    Project = var.project_name
  }
}

resource "aws_route_table_association" "a" {
  count = var.az_count
  subnet_id = element(aws_subnet.subnet.*.id, count.index)
  route_table_id = element(aws_route_table.main.*.id, count.index)
}

resource "aws_network_acl" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Project = var.project_name
  }
}

resource "aws_security_group" "outbound_only" {
  name = "${var.project_name}-outbound-only"
  vpc_id = aws_vpc.main.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Project = var.project_name
  }
}