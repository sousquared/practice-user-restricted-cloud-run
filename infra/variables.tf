variable "project" {
  description = "The ID of the project in which resources will be managed."
  type        = string
  default     = "your-project-id"  // プロジェクトIDを設定してください
}

variable "project_number" {
  description = "The project number of your GCP project"
  type        = string
  default     = "your-project-number" // プロジェクト番号を設定してください
}

variable "region" {
  description = "The region in which resources will be created."
  type        = string
  default     = "your-region"  // デフォルトのリージョンを設定
}

variable "domain" {
  description = "使用するドメイン名"
  type        = string
  default     = "example.com"  // 使用するドメイン名を設定してください
}

variable "dns_managed_zone" {
  description = "Cloud DNSのマネージドゾーン名"
  type        = string
  default     = "your-dns-zone"  // デフォルトのDNSゾーン名を設定
}

variable "iap_members" {
  description = "IAPアクセスを許可するメンバーのリスト"
  type        = list(string)
  default     = [
    "user:hoge@example.com"
    # ここにIAPアクセスを許可するメンバーを追加してください
    # 例: "user:{メールアドレスやグループアドレスなど}",
  ]
}
