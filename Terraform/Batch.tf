resource "aws_batch_job_definition" "nextstrain_job" {
  name = var.project_name
  tags = {
    Project = var.project_name
  }
  type = "container"
  platform_capabilities = ["FARGATE"]

  container_properties = jsonencode({
    image = "${data.aws_ecr_image.nextstrain_job.registry_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${data.aws_ecr_image.nextstrain_job.repository_name}:${data.aws_ecr_image.nextstrain_job.image_tag}"
    executionRoleArn = aws_iam_role.ecs_task_role.arn
    jobRoleArn = aws_iam_role.ecs_job_role.arn
    fargatePlatformConfiguration = {
      "platformVersion": "LATEST"
    },
    resourceRequirements = [
      {"type": "VCPU", "value": tostring(var.vcpus)},
      {"type": "MEMORY", "value": tostring(var.memory)}
    ]
    networkConfiguration = {
      "assignPublicIp": "ENABLED"
    }
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
          "awslogs-group" = aws_cloudwatch_log_group.log_group.name,
          "awslogs-region" = var.aws_region,
          "awslogs-stream-prefix" = "batch"
      }
    }
    environment = [
      {
        name = "S3_DESTINATION",
        value = "s3://${data.aws_s3_bucket.main_bucket.bucket}/auspice"
      },
      {
        name = "DISTRIBUTION_ID",
        value = aws_cloudfront_distribution.s3_distribution.id
      }
    ]
  })

  retry_strategy {
    attempts = var.retry_attempts
  }

  timeout {
    attempt_duration_seconds = var.timeout_seconds
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
  # Nextstrain CLI expects this exact name
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
 * Cloudwatch logging
 */

resource "aws_cloudwatch_log_group" "log_group" {
  name = var.project_name
  retention_in_days = 30
  tags = {
    Project = var.project_name
  }
}
