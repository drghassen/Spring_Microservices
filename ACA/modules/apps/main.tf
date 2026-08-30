resource "azurerm_container_app" "this" {
  for_each = local.app_definitions

  name                         = each.key
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  workload_profile_name        = "Consumption"
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.apps_managed_identity_id]
  }

  registry {
    server   = var.acr_login_server
    identity = var.apps_managed_identity_id
  }

  dynamic "secret" {
    for_each = nonsensitive(toset(keys(lookup(local.app_secrets, each.key, {}))))

    content {
      name  = secret.value
      value = local.app_secrets[each.key][secret.value]
    }
  }

  template {
    min_replicas = contains(var.active_applications, each.key) ? each.value.min_replicas : 0
    max_replicas = each.value.max_replicas

    container {
      name   = each.key
      image  = "${var.acr_login_server}/${each.key}@${var.application_image_digests[each.key]}"
      cpu    = 0.25
      memory = "0.5Gi"

      dynamic "env" {
        for_each = each.value.environment

        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = lookup(local.app_secret_environment_names, each.key, {})

        content {
          name        = env.key
          secret_name = env.value
        }
      }

      liveness_probe {
        transport               = "HTTP"
        port                    = each.value.target_port
        path                    = each.value.health_path
        initial_delay           = 60
        interval_seconds        = 30
        timeout                 = 5
        failure_count_threshold = 3
      }

      readiness_probe {
        transport               = "HTTP"
        port                    = each.value.target_port
        path                    = each.value.health_path
        initial_delay           = 5
        interval_seconds        = 10
        timeout                 = 5
        failure_count_threshold = 3
        success_count_threshold = 1
      }

      startup_probe {
        transport               = "HTTP"
        port                    = each.value.target_port
        path                    = each.value.health_path
        initial_delay           = 10
        interval_seconds        = 10
        timeout                 = 5
        failure_count_threshold = 18
      }
    }
  }

  ingress {
    external_enabled = each.value.external
    target_port      = each.value.target_port
    transport        = "http"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  # User and Games uploads use each replica's ephemeral filesystem in this POC;
  # no Azure Files or Blob volume is created here.

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_container_app_job" "database_migrations" {
  name                         = "ghassen-dridi-aca-db-migrate"
  location                     = var.location
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  workload_profile_name        = "Consumption"
  replica_timeout_in_seconds   = 600
  replica_retry_limit          = 0
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.apps_managed_identity_id]
  }

  registry {
    server   = var.acr_login_server
    identity = var.apps_managed_identity_id
  }

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  secret {
    name  = "postgres-admin-password"
    value = var.postgresql_administrator_password
  }

  secret {
    name  = "postgres-app-password"
    value = var.postgresql_application_password
  }

  template {
    container {
      name   = "database-migrations"
      image  = "${var.acr_login_server}/database-migrations@${var.database_migrations_image_digest}"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "POSTGRES_HOST"
        value = var.postgresql_server_fqdn
      }

      env {
        name  = "POSTGRES_ADMIN_USERNAME"
        value = var.postgresql_administrator_login
      }

      env {
        name        = "POSTGRES_ADMIN_PASSWORD"
        secret_name = "postgres-admin-password"
      }

      env {
        name  = "POSTGRES_APPLICATION_USERNAME"
        value = var.postgresql_application_username
      }

      env {
        name        = "POSTGRES_APPLICATION_PASSWORD"
        secret_name = "postgres-app-password"
      }

      env {
        name  = "POSTGRES_PORT"
        value = "5432"
      }

      env {
        name  = "POSTGRES_DATABASE"
        value = var.postgresql_database_name
      }

      env {
        name  = "POSTGRES_SSLMODE"
        value = "require"
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
