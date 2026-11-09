# Photo site: one private S3 bucket (site/ = Angular build, images/ = photos) served only
# through CloudFront (OAC). Adopted from the console-built stack by import; see imports.tf.
# Settings here intentionally mirror the live distribution so the first plan is a no-op.

data "aws_route53_zone" "this" {
  name         = "${var.zone_name}."
  private_zone = false
}

# --- Bucket ----------------------------------------------------------------------

resource "aws_s3_bucket" "site" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# New (not an import): the live bucket has no lifecycle rules. Only cleans up failed uploads.
# Versioning stays off (bucket is unversioned today; see docs/cost.md in aws-infrastructure).
resource "aws_s3_bucket_lifecycle_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

locals {
  site_bucket_policy = {
    Version = "2012-10-17"
    Statement = [
      # Legacy: the Lambdas list/read the bucket via this statement, not via their role policy.
      # Remove once the API is rewritten onto its own role (DynamoDB index).
      {
        Sid       = "Statement1"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObjectAttributes", "s3:GetObject", "s3:ListBucket"]
        Resource  = [aws_s3_bucket.site.arn, "${aws_s3_bucket.site.arn}/*"]
        Condition = { ArnEquals = { "aws:PrincipalArn" = aws_iam_role.lambda.arn } }
      },
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.site.arn}/*"
        Condition = { ArnLike = { "AWS:SourceArn" = aws_cloudfront_distribution.site.arn } }
      },
      # New (convention): TLS-only.
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.site.arn, "${aws_s3_bucket.site.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket     = aws_s3_bucket.site.id
  policy     = jsonencode(local.site_bucket_policy)
  depends_on = [aws_s3_bucket_public_access_block.site]
}

# --- Certificate + DNS -----------------------------------------------------------

resource "aws_acm_certificate" "site" {
  provider = aws.us_east_1

  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  for_each = {
    for o in aws_acm_certificate.site.domain_validation_options : o.domain_name => o
  }

  zone_id         = data.aws_route53_zone.this.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_route53_record" "site" {
  for_each = toset(["A", "AAAA"])

  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = each.value

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

# --- CloudFront ------------------------------------------------------------------

# Name/description are the console-generated ones; renaming is an in-place change for later.
resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "oac-photos.ryantate314.net.s3.us-east-1.amazonaws.co-md6271pkdih"
  description                       = "Created by CloudFront"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

data "aws_cloudfront_response_headers_policy" "cors_preflight" {
  name = "Managed-CORS-With-Preflight"
}

locals {
  # Origin IDs are kept exactly as created in the console (a behavior retarget is needed to rename).
  origin_site_id   = "photos.ryantate314.net.s3.us-east-1.amazonaws.com-md626c17d2v"
  origin_images_id = "photos.ryantate314.net.s3.us-east-1.amazonaws.com"
  origin_api_id    = "cyp1thm520.execute-api.us-east-1.amazonaws.com"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = ""
  default_root_object = "index.html"
  price_class         = var.price_class
  http_version        = "http2"
  aliases             = [var.domain_name]

  # Console-era tag, kept so the import is a no-op.
  tags = {
    Name = "photos-ryantate314-net"
  }

  # Angular build
  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = local.origin_site_id
    origin_path              = "/site"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  # Photos
  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = local.origin_images_id
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  # REST API, stage "api" (so /api/* maps to the stage path)
  origin {
    domain_name = "${aws_api_gateway_rest_api.photos.id}.execute-api.${var.region}.amazonaws.com"
    origin_id   = local.origin_api_id

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 30
      origin_keepalive_timeout = 5
    }
  }

  default_cache_behavior {
    target_origin_id       = local.origin_site_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
  }

  ordered_cache_behavior {
    path_pattern               = "/api/*"
    target_origin_id           = local.origin_api_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.cors_preflight.id
  }

  ordered_cache_behavior {
    path_pattern           = "/images/*"
    target_origin_id       = local.origin_images_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
  }

  # SPA fallback. With OAC and no s3:ListBucket, S3 answers 403 for missing keys, so this also
  # serves index.html for missing images (existing behavior; revisit with the API rewrite).
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.site.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
