locals {
  tags = {
    project    = "multi-region-failover"
    managed_by = "terraform"
  }
}

# The global database spans both regions: the primary cluster writes, the standby cluster
# receives storage-level replication and can be promoted during a failover.
resource "aws_rds_global_cluster" "this" {
  provider                  = aws.primary
  global_cluster_identifier = "${var.name}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.db_engine_version
  storage_encrypted         = true
  deletion_protection       = true
}

module "primary" {
  source = "./modules/regional_stack"
  providers = {
    aws = aws.primary
  }
  role              = "primary"
  name              = "${var.name}-primary"
  vpc_cidr          = var.primary.vpc_cidr
  app_image         = var.app_image
  app_desired_count = var.primary.app_desired_count
  app_cpu           = var.primary.app_cpu
  app_memory        = var.primary.app_memory
  certificate_arn   = var.certificate_arns.primary
  db_engine_version = var.db_engine_version
  db_instance_class = var.primary.db_instance_class
  db_instance_count = var.primary.db_instance_count
  global_cluster_id = aws_rds_global_cluster.this.id
}

module "standby" {
  source = "./modules/regional_stack"
  providers = {
    aws = aws.standby
  }
  role              = "standby"
  name              = "${var.name}-standby"
  vpc_cidr          = var.standby.vpc_cidr
  app_image         = var.app_image
  app_desired_count = var.standby.app_desired_count
  app_cpu           = var.standby.app_cpu
  app_memory        = var.standby.app_memory
  certificate_arn   = var.certificate_arns.standby
  db_engine_version = var.db_engine_version
  db_instance_class = var.standby.db_instance_class
  db_instance_count = var.standby.db_instance_count
  global_cluster_id = aws_rds_global_cluster.this.id

  # A secondary cluster can only join after the primary cluster exists in the global database.
  depends_on = [module.primary]
}
