resource "aws_batch_job_definition" "nextstrain_job" {
  name = var.project_name
  tags = {
    Project = var.project_name
  }
  type = "container"
  platform_capabilities = ["EC2"]

  container_properties = jsonencode({
    image = "${data.aws_ecr_image.nextstrain_job.registry_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${data.aws_ecr_image.nextstrain_job.repository_name}:${data.aws_ecr_image.nextstrain_job.image_tag}"
    executionRoleArn = aws_iam_role.ecs_task_role.arn
    jobRoleArn = aws_iam_role.ecs_job_role.arn
    resourceRequirements = [
      {"type": "VCPU", "value": tostring(var.vcpus)},
      {"type": "MEMORY", "value": tostring(var.memory)}
    ]
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
    instance_role = aws_iam_instance_profile.ecs_instance_role.arn

    # These have recent, high-performance processors, and provide
    # a very wide range of memory/cores combinations.
    instance_type = ["c6i", "m6i", "r6i", "c5", "m5", "r5"]
/*
    instance_type = [
      "m6i.large",    #  8 GiB,  2 vCPUs, $0.096000 hourly
      "r6i.large",    # 16 GiB,  2 vCPUs, $0.126000 hourly
      "m6i.xlarge",   # 16 GiB,  4 vCPUs, $0.192000 hourly
      "r6i.xlarge",   # 32 GiB,  4 vCPUs, $0.252000 hourly
      "c6i.2xlarge",  # 16 GiB,  8 vCPUs, $0.340000 hourly
      "m6i.xlarge",   # 32 GiB,  8 vCPUs, $0.384000 hourly

      "m5.large",     #  8 GiB,  2 vCPUs, $0.096000 hourly
      "r5.large",     # 16 GiB,  2 vCPUs, $0.126000 hourly
      "m5.xlarge",    # 16 GiB,  4 vCPUs, $0.192000 hourly
      "r5.xlarge",    # 32 GiB,  4 vCPUs, $0.252000 hourly
      "c5.2xlarge",   # 16 GiB,  8 vCPUs, $0.340000 hourly
      "m5.xlarge",    # 32 GiB,  8 vCPUs, $0.384000 hourly
    ]
*/

    max_vcpus = 16
    min_vcpus = 0

    security_group_ids = [
      aws_security_group.outbound_only.id,
    ]

    subnets = aws_subnet.subnet.*.id

    type = "EC2"
  }

  service_role = aws_iam_role.batch_service_role.arn
  type         = "MANAGED"
  depends_on   = [aws_iam_role_policy_attachment.batch_service_role]
}


resource "aws_batch_job_queue" "nextstrain_queue" {
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
