output "load_balancer_ip" {
  value       = google_compute_global_address.hello_lb_ip.address
  description = "ロードバランサーの静的IPアドレス"
}
