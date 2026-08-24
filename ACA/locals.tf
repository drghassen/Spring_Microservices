locals {
  name_prefix = "${var.project_name}-${var.environment}"

  default_tags = {
    Project     = "Ghassen Dridi"
    Environment = "aca"
    ManagedBy   = "Terraform"
    Workload    = "Ghassen Dridi"
  }

  effective_tags = merge(local.default_tags, var.tags)
}
