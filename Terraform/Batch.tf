#####################################################################################
#####################################################################################
##
## Job definition
##

resource "aws_batch_job_definition" "nextstrain_job" {
  name = var.project_name
  tags = {
    Project = var.project_name
  }
  propagate_tags = true
  type = "container"
  platform_capabilities = ["EC2"]

  container_properties = jsonencode({
    image = "${data.aws_ecr_image.nextstrain_job.registry_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${data.aws_ecr_image.nextstrain_job.repository_name}:${data.aws_ecr_image.nextstrain_job.image_tag}"
    command = [
      "--profile",
      "puerto-rico_profiles/puerto-rico_open/"
    ]
    executionRoleArn = aws_iam_role.ecs_task_role.arn
    jobRoleArn = aws_iam_role.ecs_job_role.arn
    resourceRequirements = [
      {"type": "VCPU", "value": 4},
      {"type": "MEMORY", "value": 14336}
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
        name = "S3_AUSPICE_DESTINATION",
        value = "s3://${data.aws_s3_bucket.main_bucket.bucket}/auspice"
      },
      {
        name = "S3_JOBS_DESTINATION",
        value = "s3://${aws_s3_bucket.jobs_bucket.bucket}"
      },
      {
        name = "CLOUDFRONT_DISTRIBUTION_ID",
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

#####################################################################################
#####################################################################################
##
## Job scheduling
##

resource "aws_cloudwatch_event_rule" "weekly_run" {
  name        = "covid-19-puerto-rico-nextstrain-weekly-run"
  description = "Run the weekly Nextstrain build."
  schedule_expression = "cron(55 09 ? * 1 *)"
}

resource "aws_cloudwatch_event_target" "weekly_run" {
  target_id = "covid-19-puerto-rico-nextstrain-weekly-run"
  rule = aws_cloudwatch_event_rule.weekly_run.name
  arn = aws_batch_job_queue.nextstrain_queue.arn
  role_arn = aws_iam_role.ecs_events_role.arn

  batch_target {
    job_definition = aws_batch_job_definition.nextstrain_job.arn
    job_name       = aws_batch_job_definition.nextstrain_job.name
  }
}


#####################################################################################
#####################################################################################
##
## Compute environment
##

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

    max_vcpus = 16
    # Important: 0 = compute environment scales down to nothing
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
