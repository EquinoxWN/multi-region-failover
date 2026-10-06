output "summary" {
  description = "Endpoints and the settings that define the stack's shape, for tests and the runbook."
  value = {
    role                     = var.role
    alb_dns_name             = aws_lb.this.dns_name
    db_cluster_id            = aws_rds_cluster.this.id
    db_global_cluster        = aws_rds_cluster.this.global_cluster_identifier
    db_instance_count        = length(aws_rds_cluster_instance.this)
    db_instance_class        = var.db_instance_class
    db_engine_version        = aws_rds_cluster.this.engine_version
    db_encrypted             = aws_rds_cluster.this.storage_encrypted
    db_deletion_protection   = aws_rds_cluster.this.deletion_protection
    db_backup_retention      = aws_rds_cluster.this.backup_retention_period
    db_has_own_credentials   = aws_rds_cluster.this.manage_master_user_password == true
    db_public                = anytrue(aws_rds_cluster_instance.this[*].publicly_accessible)
    app_desired_count        = aws_ecs_service.api.desired_count
    app_public_ip            = one(aws_ecs_service.api.network_configuration[*].assign_public_ip)
    app_image                = var.app_image
    az_count                 = length(aws_subnet.private)
    https_policy             = aws_lb_listener.https.ssl_policy
    http_action              = one(aws_lb_listener.http_redirect.default_action[*].type)
    log_retention_days       = aws_cloudwatch_log_group.app.retention_in_days
    kms_rotation             = aws_kms_key.this.enable_key_rotation
    kms_logs_principal       = jsondecode(aws_kms_key.this.policy).Statement[1].Principal.Service
    db_ingress_from_app_only = aws_vpc_security_group_ingress_rule.db_from_app.referenced_security_group_id == aws_security_group.app.id
  }
}
