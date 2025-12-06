resource "aws_cloudfront_distribution" "main" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.project_name} CloudFront distribution"
  price_class     = var.price_class
  aliases         = var.domain_name != "" ? [var.domain_name] : []
  web_acl_id      = var.waf_acl_id != "" ? var.waf_acl_id : null
  default_root_object = "index.html"

  # S3 origin for frontend static files
  origin {
    domain_name = var.s3_bucket_regional_domain_name
    origin_id   = "s3-frontend"

    s3_origin_config {
      origin_access_identity = var.cloudfront_oai_path
    }
  }

  # ALB origin for backend API
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = var.certificate_arn != "" ? "https-only" : "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default cache behavior (for frontend static files from S3)
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-frontend"

    forwarded_values {
      query_string = false
      headers      = []

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600    # 1 hour
    max_ttl                = 86400   # 24 hours
    compress               = true

    # Custom error responses for SPA routing
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_routing.arn
    }
  }

  # Custom error responses for SPA routing
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  # Cache behavior for /tiles/* (24-hour TTL, query string forwarding)
  ordered_cache_behavior {
    path_pattern     = "/tiles/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "alb-origin"

    forwarded_values {
      query_string = true
      headers      = []

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 3600
    default_ttl            = 86400
    max_ttl                = 86400
    compress               = true
  }

  # Cache behavior for /api/* (no caching)
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "alb-origin"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Host"]

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Conditional SSL certificate configuration
  viewer_certificate {
    cloudfront_default_certificate = var.certificate_arn == "" ? true : false
    acm_certificate_arn            = var.certificate_arn != "" ? var.certificate_arn : null
    ssl_support_method             = var.certificate_arn != "" ? "sni-only" : null
    minimum_protocol_version       = var.certificate_arn != "" ? "TLSv1.2_2021" : "TLSv1"
  }

  tags = var.tags
}

# CloudFront function for SPA routing
resource "aws_cloudfront_function" "spa_routing" {
  name    = "${var.project_name}-spa-routing"
  runtime = "cloudfront-js-1.0"
  comment = "Rewrite requests for SPA routing"
  publish = true
  code    = <<-EOT
function handler(event) {
    var request = event.request;
    var uri = request.uri;
    
    // Check if the URI has a file extension
    if (!uri.includes('.')) {
        // No extension, assume it's a route - serve index.html
        request.uri = '/index.html';
    }
    
    return request;
}
EOT
}

