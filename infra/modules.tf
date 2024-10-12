# load balancer用の静的IP
resource "google_compute_global_address" "hello_lb_ip" {
  name         = "hello-lb-ip"
  description  = "load balancerの静的IP"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
  project      = var.project
}


# Cloud Run サービス
resource "google_cloud_run_v2_service" "hello_cloud_run" {
  name        = "hello"
  location    = var.region
  description = "cloud run service"
  ingress     = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"  # 内部ロードバランサーからのトラフィックのみを許可します

  template {
    containers {
      name  = "hello"
      image = "us-docker.pkg.dev/cloudrun/container/hello:latest"
      resources {
        cpu_idle = false
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }

  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"  # 最新のリビジョン（デプロイメント）にトラフィックを送信することを指定
    percent = 100
  }

  deletion_protection = false  # 削除保護を無効にする (terraform destroy時に削除できるようにする)
}

# Cloud Runの未認証呼び出し許可policy (本番環境ではmembersに適切な値を設定すること)
data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

# Cloud Runの未認証呼び出し許可を付与
resource "google_cloud_run_service_iam_policy" "noauth" {
  location = google_cloud_run_v2_service.hello_cloud_run.location
  project  = var.project
  service  = google_cloud_run_v2_service.hello_cloud_run.name

  policy_data = data.google_iam_policy.noauth.policy_data
}

# Load Balancerのserverless NEG
resource "google_compute_region_network_endpoint_group" "hello_neg" {
  name                  = "hello-neg"
  network_endpoint_type = "SERVERLESS"
  region                = "asia-northeast1"
  # cloud runのserviceを指定
  cloud_run {
    service = google_cloud_run_v2_service.hello_cloud_run.name
  }
}

# Load Balancerのcloud armor policy
resource "google_compute_security_policy" "hello_policy" {
  name        = "hello-policy"
  description = "Load Balancer用のcloud armor policy"
  rule {
    action   = "allow"
    priority = 1000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        # FIXME: your ip address
        src_ip_ranges = ["IP_ADDRESS"]
      }
    }
    description = "my home global ip address"
  }
  rule {
    action   = "deny(403)"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "default rule"
  }
  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }
}

# load balancerのbackend service
resource "google_compute_backend_service" "hello_backend_service" {
  name                  = "hello-backend-service"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  load_balancing_scheme = "EXTERNAL_MANAGED"

  # cloud armor policyを指定
  security_policy = google_compute_security_policy.hello_policy.id

  backend {
    group = google_compute_region_network_endpoint_group.hello_neg.self_link
  }
}

# url map
resource "google_compute_url_map" "hello_url_map" {
  name        = "hello-lb"
  description = "load balancer用のlb"

  default_service = google_compute_backend_service.hello_backend_service.id

  path_matcher {
    name            = "hello-apps"
    default_service = google_compute_backend_service.hello_backend_service.id
  }
}

resource "google_compute_target_http_proxy" "hello_target_http_proxy" {
  name    = "predictor-target-http-proxy"
  url_map = google_compute_url_map.hello_url_map.id
}

# フロントエンドの設定(http)
resource "google_compute_global_forwarding_rule" "hello_forwarding_rule_http" {
  name                  = "hello-forwarding-rule-http"
  description           = "load balancerのforwarding rule(http)"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  target                = google_compute_target_http_proxy.hello_target_http_proxy.id
  ip_address            = google_compute_global_address.hello_lb_ip.address
  ip_protocol           = "TCP"
  port_range            = "80"
}
