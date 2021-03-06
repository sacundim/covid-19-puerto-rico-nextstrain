#####################################################################################
#####################################################################################
##
## Job definition
##

locals {
  # If these are not strings we get errors
  cores = "4"
  mem_mb = "15360"

  registry = data.aws_ecr_image.nextstrain_job.registry_id
  region = data.aws_region.current.name
  repository = data.aws_ecr_image.nextstrain_job.repository_name
  tag = data.aws_ecr_image.nextstrain_job.image_tag
}

resource "aws_batch_job_definition" "nextstrain_job" {
  name = var.project_name
  tags = {
    Project = var.project_name
  }
  propagate_tags = true
  type = "container"
  platform_capabilities = ["EC2"]

  container_properties = jsonencode({
    image = "${local.registry}.dkr.ecr.${local.region}.amazonaws.com/${local.repository}:${local.tag}"
    command = [
      # Default: run the whole build. Override the command to do something different
      "--profile", "puerto-rico_profiles/puerto-rico_open/"
    ]
    executionRoleArn = aws_iam_role.ecs_task_role.arn
    jobRoleArn = aws_iam_role.ecs_job_role.arn
    resourceRequirements = [
      {"type": "VCPU", "value": local.cores},
      {"type": "MEMORY", "value": local.mem_mb}
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
    attempts = 2
    evaluate_on_exit {
      on_status_reason = "Host EC2*"
      action = "RETRY"
    }
    evaluate_on_exit {
      on_reason = "*"
      action = "EXIT"
    }
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

resource "aws_cloudwatch_event_target" "weekly_run_6m" {
  target_id = "covid-19-puerto-rico-nextstrain-6m-run"
  rule = aws_cloudwatch_event_rule.weekly_run.name
  arn = aws_batch_job_queue.nextstrain_queue.arn
  role_arn = aws_iam_role.ecs_events_role.arn

  batch_target {
    job_definition = aws_batch_job_definition.nextstrain_job.arn
    job_name       = aws_batch_job_definition.nextstrain_job.name
  }

  input = jsonencode({
    "ContainerOverrides": {
      "Command": [
        "--profile", "puerto-rico_profiles/puerto-rico_open/",
        "--config", "active_builds=puerto-rico"
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "weekly_run_all_time" {
  target_id = "covid-19-puerto-rico-nextstrain-all-time-run"
  rule = aws_cloudwatch_event_rule.weekly_run.name
  arn = aws_batch_job_queue.nextstrain_queue.arn
  role_arn = aws_iam_role.ecs_events_role.arn

  batch_target {
    job_definition = aws_batch_job_definition.nextstrain_job.arn
    job_name       = aws_batch_job_definition.nextstrain_job.name
  }

  input = jsonencode({
    "ContainerOverrides": {
      "Command": [
        "--profile", "puerto-rico_profiles/puerto-rico_open/",
        "--config", "active_builds=puerto-rico_all-time"
      ]
    }
  })
}


#####################################################################################
#####################################################################################
##
## Compute environment
##

resource "aws_batch_compute_environment" "nextstrain" {
  # If we don't do this prefix/create_before_destroy business
  # we get errors when we try to destroy a compute environment.
  # See:
  #
  # * https://github.com/hashicorp/terraform-provider-aws/issues/2044
  # * https://discuss.hashicorp.com/t/error-error-deleting-batch-compute-environment-cannot-delete-found-existing-jobqueue-relationship/5408
  #
  compute_environment_name_prefix = "${var.project_name}-compute-environment-"
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Project = var.project_name
  }

  compute_resources {
    instance_role = aws_iam_instance_profile.ecs_instance_role.arn

    # These have reasonably recent, high-performance processors, and
    # provide a very wide range of memory/cores combinations.
    instance_type = [
      "c6i", "m6i", "r6i",
      # As of 2022-05-09, Batch doesn't yet support these:
      # "c6a", "m6a", "r6a",
      "c5",  "m5",  "r5"
      # The single-threaded performance of these is so much
      # slower that it actually takes longer and costs us more
      # "c5a", "m5a", "r5a"
    ]

    max_vcpus = 16
    # Important: 0 = compute environment scales down to nothing
    min_vcpus = 0

    security_group_ids = [
      aws_security_group.outbound_only.id,
    ]

    subnets = aws_subnet.subnet.*.id

    type = "SPOT"
    allocation_strategy = "BEST_FIT"

    # If not set, it will bid up to 100% of On-Demand:
    bid_percentage = 50

    spot_iam_fleet_role = aws_iam_role.spot_fleet_tagging_role.arn
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
