locals {
  primary = var.role == "primary"
}

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "this" {
  description             = "${var.name}: Aurora storage and API logs"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  # The account administers the key; CloudWatch Logs in this region may use it, but only for
  # this stack's API log group (without this statement creating the encrypted log group fails).
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministers"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudWatchLogsForTheApiLogGroup"
        Effect    = "Allow"
        Principal = { Service = "logs.${data.aws_region.current.region}.amazonaws.com" }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/${var.name}/api"
          }
        }
      },
    ]
  })
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = aws_subnet.private[*].id
}

# In the primary region the cluster is the writer; in the standby region it joins the global
# database as a secondary (no credentials of its own, it replicates the primary's).
resource "aws_rds_cluster" "this" {
  cluster_identifier                  = var.name
  engine                              = "aurora-postgresql"
  engine_version                      = var.db_engine_version
  global_cluster_identifier           = var.global_cluster_id
  db_subnet_group_name                = aws_db_subnet_group.this.name
  vpc_security_group_ids              = [aws_security_group.db.id]
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.this.arn
  deletion_protection                 = true
  backup_retention_period             = 7
  copy_tags_to_snapshot               = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${var.name}-final"
  database_name                       = local.primary ? "app" : null
  master_username                     = local.primary ? "app_admin" : null
  manage_master_user_password         = local.primary ? true : null
  iam_database_authentication_enabled = true

  lifecycle {
    # After a failover the roles swap inside AWS; Terraform must not try to undo that.
    ignore_changes = [global_cluster_identifier, replication_source_identifier]
  }
}

resource "aws_rds_cluster_instance" "this" {
  count                      = var.db_instance_count
  identifier                 = "${var.name}-${count.index}"
  cluster_identifier         = aws_rds_cluster.this.id
  instance_class             = var.db_instance_class
  engine                     = aws_rds_cluster.this.engine
  engine_version             = aws_rds_cluster.this.engine_version
  db_subnet_group_name       = aws_db_subnet_group.this.name
  publicly_accessible        = false
  auto_minor_version_upgrade = false
}
