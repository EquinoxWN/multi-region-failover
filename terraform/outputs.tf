output "global_cluster_id" {
  description = "Aurora global database identifier."
  value       = aws_rds_global_cluster.this.id
}

output "primary" {
  description = "Endpoints and shape of the primary stack."
  value       = module.primary.summary
}

output "standby" {
  description = "Endpoints and shape of the warm standby stack."
  value       = module.standby.summary
}
