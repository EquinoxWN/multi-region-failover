# Offline tests: both AWS providers are mocked, so `terraform test` plans and applies the whole
# two-region configuration without an AWS account and checks what it would build.

mock_provider "aws" {
  alias = "primary"
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/mrf/0123456789abcdef", dns_name = "mrf.us-east-1.elb.amazonaws.com" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/api/0123456789abcdef" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mrf-exec" }
  }
  mock_resource "aws_ecs_task_definition" {
    defaults = { arn = "arn:aws:ecs:us-east-1:123456789012:task-definition/mrf-api:1" }
  }
  mock_resource "aws_ecs_cluster" {
    defaults = { arn = "arn:aws:ecs:us-east-1:123456789012:cluster/mrf" }
  }
  mock_resource "aws_rds_cluster" {
    defaults = { arn = "arn:aws:rds:us-east-1:123456789012:cluster:mrf", endpoint = "mrf.cluster-abc.us-east-1.rds.amazonaws.com" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:/mrf/api" }
  }
}

mock_provider "aws" {
  alias = "standby"
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-west-2a", "us-west-2b", "us-west-2c"] }
  }
  mock_data "aws_region" {
    defaults = { region = "us-west-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/mrf/0123456789abcdef", dns_name = "mrf.us-west-2.elb.amazonaws.com" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-west-2:123456789012:targetgroup/api/0123456789abcdef" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-west-2:123456789012:key/11111111-2222-3333-4444-555555555555" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mrf-exec" }
  }
  mock_resource "aws_ecs_task_definition" {
    defaults = { arn = "arn:aws:ecs:us-west-2:123456789012:task-definition/mrf-api:1" }
  }
  mock_resource "aws_ecs_cluster" {
    defaults = { arn = "arn:aws:ecs:us-west-2:123456789012:cluster/mrf" }
  }
  mock_resource "aws_rds_cluster" {
    defaults = { arn = "arn:aws:rds:us-west-2:123456789012:cluster:mrf", endpoint = "mrf.cluster-abc.us-west-2.rds.amazonaws.com" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-west-2:123456789012:log-group:/mrf/api" }
  }
}

variables {
  app_image = "123456789012.dkr.ecr.us-east-1.amazonaws.com/api@sha256:0000000000000000000000000000000000000000000000000000000000000001"
  certificate_arns = {
    primary = "arn:aws:acm:us-east-1:123456789012:certificate/primary"
    standby = "arn:aws:acm:us-west-2:123456789012:certificate/standby"
  }
}

run "both_regions_build_the_same_stack" {
  command = apply

  assert {
    condition     = output.primary.az_count == output.standby.az_count && output.primary.az_count == 2
    error_message = "Both regions must spread over the same number of availability zones."
  }
  assert {
    condition     = output.primary.app_image == output.standby.app_image
    error_message = "Both regions must run the same image digest."
  }
  assert {
    condition     = output.primary.db_engine_version == output.standby.db_engine_version
    error_message = "A global database needs the same engine version in both regions."
  }
  assert {
    condition     = output.primary.https_policy == output.standby.https_policy && output.primary.http_action == "redirect" && output.standby.http_action == "redirect"
    error_message = "Both load balancers must serve HTTPS with the same policy and only redirect plain HTTP."
  }
  assert {
    condition     = output.primary.role == "primary" && output.standby.role == "standby"
    error_message = "Roles are wired to the wrong modules."
  }
}

run "the_standby_is_warm_but_minimal" {
  command = apply

  assert {
    condition     = output.standby.app_desired_count == 1 && output.primary.app_desired_count == 3
    error_message = "The standby runs one task (warm) while the primary runs three."
  }
  assert {
    condition     = output.standby.db_instance_count == 1 && output.primary.db_instance_count == 2
    error_message = "The standby keeps one database instance, the primary a writer and a reader."
  }
}

run "both_clusters_belong_to_one_encrypted_global_database" {
  command = apply

  assert {
    condition     = output.primary.db_global_cluster == output.global_cluster_id && output.standby.db_global_cluster == output.global_cluster_id
    error_message = "Both regional clusters must join the same global database."
  }
  assert {
    condition     = aws_rds_global_cluster.this.storage_encrypted && aws_rds_global_cluster.this.deletion_protection
    error_message = "The global database must be encrypted and protected from deletion."
  }
  assert {
    condition     = output.primary.db_encrypted && output.standby.db_encrypted && output.primary.kms_rotation && output.standby.kms_rotation
    error_message = "Each region encrypts with its own key, with rotation on."
  }
  assert {
    condition     = output.primary.kms_logs_principal == "logs.us-east-1.amazonaws.com" && output.standby.kms_logs_principal == "logs.us-west-2.amazonaws.com"
    error_message = "Each region's key must let that region's CloudWatch Logs encrypt the API log group."
  }
  assert {
    condition     = output.primary.db_has_own_credentials && !output.standby.db_has_own_credentials
    error_message = "Only the primary cluster has credentials; the secondary replicates them."
  }
  assert {
    condition     = output.primary.db_deletion_protection && output.standby.db_deletion_protection && output.primary.db_backup_retention >= 7 && output.standby.db_backup_retention >= 7
    error_message = "Clusters need deletion protection and at least a week of backups."
  }
}

run "nothing_private_is_reachable_from_the_internet" {
  command = apply

  assert {
    condition     = !output.primary.db_public && !output.standby.db_public
    error_message = "Database instances must not be publicly accessible."
  }
  assert {
    condition     = !output.primary.app_public_ip && !output.standby.app_public_ip
    error_message = "API tasks must run without public IP addresses."
  }
  assert {
    condition     = output.primary.db_ingress_from_app_only && output.standby.db_ingress_from_app_only
    error_message = "The database must only accept connections from the API's security group."
  }
  assert {
    condition     = output.primary.log_retention_days == 30
    error_message = "API logs are kept for 30 days."
  }
}

run "regions_must_differ" {
  command = plan
  variables {
    standby_region = "us-east-1"
  }
  expect_failures = [var.standby_region]
}

run "a_standby_of_zero_would_be_pilot_light_not_warm" {
  command = plan
  variables {
    standby = {
      vpc_cidr          = "10.20.0.0/16"
      app_desired_count = 0
      app_cpu           = 512
      app_memory        = 1024
      db_instance_class = "db.r6g.large"
      db_instance_count = 1
    }
  }
  expect_failures = [var.standby]
}

run "a_standby_larger_than_the_primary_is_refused" {
  command = plan
  variables {
    standby = {
      vpc_cidr          = "10.20.0.0/16"
      app_desired_count = 5
      app_cpu           = 512
      app_memory        = 1024
      db_instance_class = "db.r6g.large"
      db_instance_count = 1
    }
  }
  expect_failures = [var.standby]
}

run "images_must_be_pinned_by_digest" {
  command = plan
  variables {
    app_image = "123456789012.dkr.ecr.us-east-1.amazonaws.com/api:latest"
  }
  expect_failures = [var.app_image]
}

run "overlapping_vpc_ranges_are_refused" {
  command = plan
  variables {
    standby = {
      vpc_cidr          = "10.10.0.0/16"
      app_desired_count = 1
      app_cpu           = 512
      app_memory        = 1024
      db_instance_class = "db.r6g.large"
      db_instance_count = 1
    }
  }
  expect_failures = [var.standby]
}
