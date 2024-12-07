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

# Cloud Runの未認証呼び出し許可policy 
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

# IAPクライアントの設定
resource "google_iap_client" "project_client" {
  display_name = "Hello Cloud Run Client"
  brand        = "projects/${var.project}/brands/${var.project_number}"
}

# IAPの設定
resource "google_iap_web_backend_service_iam_binding" "binding" {
  project = var.project
  web_backend_service = google_compute_backend_service.hello_backend_service.name
  role = "roles/iap.httpsResourceAccessor"
  members = var.iap_members
}

# バックエンドサービスにIAPを有効化
resource "google_compute_backend_service" "hello_backend_service" {
  name                  = "hello-backend-service"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_region_network_endpoint_group.hello_neg.self_link
  }

  iap {
    oauth2_client_id     = google_iap_client.project_client.client_id
    oauth2_client_secret = google_iap_client.project_client.secret
    enabled              = true
  }
}

# IAPサービスアカウントの作成
resource "google_project_service_identity" "iap_sa" {
  provider = google-beta
  project  = var.project
  service  = "iap.googleapis.com"
}

# IAPサービスアカウントの作成を待ってから実行されるように依存関係を追加
resource "google_cloud_run_v2_service_iam_member" "iap_invoker" {
  name = google_cloud_run_v2_service.hello_cloud_run.name
  location = var.region
  project  = var.project
  role     = "roles/run.invoker"
  member   = google_project_service_identity.iap_sa.member

  depends_on = [
    google_project_service_identity.iap_sa
  ]
}

resource "google_compute_url_map" "hello_url_map" {
  name        = "hello-lb"
  description = "load balancer用のlb"

  default_service = google_compute_backend_service.hello_backend_service.id

  path_matcher {
    name            = "hello-apps"
    default_service = google_compute_backend_service.hello_backend_service.id
  }
}

# HTTPSプロキシの設定
resource "google_compute_target_https_proxy" "hello_target_https_proxy" {
  name             = "hello-target-https-proxy"
  url_map          = google_compute_url_map.hello_url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.hello_ssl_cert.id]
}

# マネージドSSL証明書の設定
resource "google_compute_managed_ssl_certificate" "hello_ssl_cert" {
  name = "hello-ssl-cert"
  managed {
    domains = [var.domain]
  }
}

# フロントエンドの設定(https)
resource "google_compute_global_forwarding_rule" "hello_forwarding_rule_https" {
  name                  = "hello-forwarding-rule-https"
  description           = "load balancerのforwarding rule(https)"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  target                = google_compute_target_https_proxy.hello_target_https_proxy.id
  ip_address            = google_compute_global_address.hello_lb_ip.address
  ip_protocol           = "TCP"
  port_range            = "443"
}


# DNSレコードの設定
resource "google_dns_record_set" "hello" {
  name = "${var.domain}."
  type = "A"
  ttl  = 300

  managed_zone = var.dns_managed_zone  # 変数を使用

  rrdatas = [google_compute_global_address.hello_lb_ip.address]
}

resource "google_dns_record_set" "hello_cname" {
  name = "_acme-challenge.${var.domain}."
  type = "CNAME"
  ttl  = 300

  managed_zone = var.dns_managed_zone  # 変数を使用

  rrdatas = ["gv-${substr(var.domain, 0, 32)}.${var.domain}."]
}

# SSL証明書の状態を取得するためのデータソース
data "google_compute_ssl_certificate" "hello_cert" {
  name = google_compute_managed_ssl_certificate.hello_ssl_cert.name
}
