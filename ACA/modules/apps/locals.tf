locals {
  # Redis provisioning is an explicit prerequisite for these workloads, but
  # Terraform cannot guarantee startup order among the release applications.
  # Their expected runtime order remains config-server, discovery-service,
  # gateway, then the business services and client.
  app_definitions = {
    client = {
      target_port  = 8080
      external     = true
      min_replicas = 1
      max_replicas = 2
      health_path  = "/"
      environment = {
        NGINX_DEPLOYMENT_TARGET = "aca"
      }
    }
    config-server = {
      target_port  = 8888
      external     = false
      min_replicas = 1
      max_replicas = 1
      health_path  = "/actuator/health"
      environment = {
        SPRING_PROFILES_ACTIVE = "native"
      }
    }
    discovery-service = {
      target_port  = 8761
      external     = false
      min_replicas = 1
      max_replicas = 1
      health_path  = "/actuator/health"
      environment = {
        SPRING_PROFILES_ACTIVE    = "aca"
        CONFIG_SERVER_URL         = "optional:configserver:http://config-server"
        EUREKA_HOSTNAME_DISCOVERY = "discovery-service"
      }
    }
    gateway = {
      target_port    = 8222
      external       = false
      min_replicas   = 1
      max_replicas   = 2
      health_path    = "/actuator/health"
      liveness_path  = "/actuator/health/liveness"
      readiness_path = "/actuator/health/readiness"
      startup_path   = "/actuator/health/liveness"
      environment = {
        SPRING_PROFILES_ACTIVE         = "aca"
        CONFIG_SERVER_URL              = "optional:configserver:http://config-server"
        EUREKA_DEFAULT_ZONE            = "http://discovery-service/eureka"
        EUREKA_HOSTNAME_GATEWAY        = "gateway"
        CORS_ALLOWED_ORIGINS           = "https://client.${var.container_app_environment_default_domain}"
        REDIS_HOST                     = "redis"
        REDIS_PORT                     = "6379"
        RATE_LIMIT_AUTH_REPLENISH_RATE = tostring(var.rate_limit_auth_replenish_rate)
        RATE_LIMIT_AUTH_BURST_CAPACITY = tostring(var.rate_limit_auth_burst_capacity)
        IP_BLOCKING_MODE               = "SHADOW"
        IP_BLOCKING_WINDOW_SECONDS     = "10"
        IP_BLOCKING_429_THRESHOLD      = "3"
        IP_BLOCKING_WINDOWS_REQUIRED   = "3"
        IP_BLOCKING_DURATION_SECONDS   = "60"
      }
    }
    games-service = {
      target_port  = 8070
      external     = false
      min_replicas = 1
      max_replicas = 1
      health_path  = "/actuator/health"
      environment = {
        SPRING_PROFILES_ACTIVE = "aca"
        CONFIG_SERVER_URL      = "optional:configserver:http://config-server"
        EUREKA_DEFAULT_ZONE    = "http://discovery-service/eureka"
        EUREKA_HOSTNAME_GAMES  = "games-service"
        DB_URL                 = "jdbc:postgresql://${var.postgresql_server_fqdn}:5432/${var.postgresql_database_name}"
        DB_USERNAME            = var.postgresql_application_username
        UPLOADS_GAMES_DIR      = "/app/uploads/games"
      }
    }
    library-service = {
      target_port  = 8020
      external     = false
      min_replicas = 1
      max_replicas = 2
      health_path  = "/actuator/health"
      environment = {
        SPRING_PROFILES_ACTIVE    = "aca"
        CONFIG_SERVER_URL         = "optional:configserver:http://config-server"
        EUREKA_DEFAULT_ZONE       = "http://discovery-service/eureka"
        EUREKA_HOSTNAME_LIBRARY   = "library-service"
        MONGO_AUTO_INDEX_CREATION = "false"
      }
    }
    order-service = {
      target_port  = 8060
      external     = false
      min_replicas = 1
      max_replicas = 2
      health_path  = "/actuator/health"
      environment = {
        SPRING_PROFILES_ACTIVE = "aca"
        CONFIG_SERVER_URL      = "optional:configserver:http://config-server"
        EUREKA_DEFAULT_ZONE    = "http://discovery-service/eureka"
        EUREKA_HOSTNAME_ORDER  = "order-service"
        DB_URL                 = "jdbc:postgresql://${var.postgresql_server_fqdn}:5432/${var.postgresql_database_name}"
        DB_USERNAME            = var.postgresql_application_username
      }
    }
    payment-service = {
      target_port  = 8050
      external     = false
      min_replicas = 1
      max_replicas = 2
      health_path  = "/actuator/health"
      environment = {
        SPRING_PROFILES_ACTIVE  = "aca"
        CONFIG_SERVER_URL       = "optional:configserver:http://config-server"
        EUREKA_DEFAULT_ZONE     = "http://discovery-service/eureka"
        EUREKA_HOSTNAME_PAYMENT = "payment-service"
        DB_URL                  = "jdbc:postgresql://${var.postgresql_server_fqdn}:5432/${var.postgresql_database_name}"
        DB_USERNAME             = var.postgresql_application_username
      }
    }
    user-service = {
      target_port  = 8090
      external     = false
      min_replicas = 1
      max_replicas = 1
      health_path  = "/actuator/health"
      environment = {
        SPRING_PROFILES_ACTIVE    = "aca"
        CONFIG_SERVER_URL         = "optional:configserver:http://config-server"
        EUREKA_DEFAULT_ZONE       = "http://discovery-service/eureka"
        EUREKA_HOSTNAME_USER      = "user-service"
        UPLOADS_USER_DIR          = "/app/uploads/user"
        MONGO_AUTO_INDEX_CREATION = "false"
      }
    }
  }

  app_secrets = {
    config-server = {
      jwt-secret = var.application_jwt_secret
    }
    gateway = {
      jwt-secret = var.application_jwt_secret
    }
    games-service = {
      db-password = var.postgresql_application_password
    }
    library-service = {
      mongo-uri = var.cosmos_mongodb_uri
    }
    order-service = {
      db-password = var.postgresql_application_password
    }
    payment-service = {
      db-password = var.postgresql_application_password
    }
    user-service = {
      mongo-uri      = var.cosmos_mongodb_uri
      jwt-secret     = var.application_jwt_secret
      admin-password = var.application_admin_password
    }
  }

  app_secret_environment_names = {
    config-server = {
      JWT_SECRET = "jwt-secret"
    }
    gateway = {
      JWT_SECRET = "jwt-secret"
    }
    games-service = {
      DB_PASSWORD = "db-password"
    }
    library-service = {
      MONGO_URI = "mongo-uri"
    }
    order-service = {
      DB_PASSWORD = "db-password"
    }
    payment-service = {
      DB_PASSWORD = "db-password"
    }
    user-service = {
      MONGO_URI      = "mongo-uri"
      JWT_SECRET     = "jwt-secret"
      ADMIN_PASSWORD = "admin-password"
    }
  }
}
