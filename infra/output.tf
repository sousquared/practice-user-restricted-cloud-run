output "domain" {
  description = "デプロイされたアプリケーションのドメイン名"
  value       = var.domain
}

output "lb_ip" {
  description = "ロードバランサーの静的IPアドレス"
  value       = google_compute_global_address.hello_lb_ip.address
}

output "url" {
  description = "アプリケーションのURL"
  value       = "https://${var.domain}"
}

output "certificate_status" {
  description = "SSL証明書のステータス"
  value = {
    id = data.google_compute_ssl_certificate.hello_cert.certificate_id
    creation_timestamp = data.google_compute_ssl_certificate.hello_cert.creation_timestamp
    expire_time = data.google_compute_ssl_certificate.hello_cert.expire_time
  }
}
