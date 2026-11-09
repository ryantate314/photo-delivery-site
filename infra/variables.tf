variable "workload" {
  type        = string
  description = "Workload name, lowercase-with-hyphens."
  default     = "photos"
}

variable "env" {
  type        = string
  description = "dev or prod."
  default     = "prod"

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name" {
  type        = string
  description = "Existing site/photo bucket (adopted by import; the name is fixed)."
  default     = "photos.ryantate314.net"
}

variable "domain_name" {
  type        = string
  description = "Public hostname served by CloudFront."
  default     = "photos.ryantate314.net"
}

variable "zone_name" {
  type        = string
  description = "Existing Route 53 hosted zone (looked up by name; never created here)."
  default     = "ryantate314.net"
}

variable "price_class" {
  type        = string
  description = "Matches the live distribution (PriceClass_All). PriceClass_100 would be cheaper; change deliberately in a later PR."
  default     = "PriceClass_All"
}
