# CloudFront Module

This module creates a CloudFront CDN distribution for caching and distributing content from the Application Load Balancer.

## Architecture

CloudFront sits in front of the ALB to provide:
- **Edge Caching**: Cache tiles at 400+ edge locations worldwide
- **HTTPS Enforcement**: Redirect HTTP to HTTPS
- **Custom Domain**: Optional custom domain with ACM certificate
- **WAF Integration**: Optional Web Application Firewall protection
- **Compression**: Automatic gzip compression

## Cache Behaviors

The distribution implements three cache behaviors:

### 1. Tiles Cache Behavior (`/tiles/*`)
- **TTL**: 24 hours (86400 seconds)
- **Query Strings**: Forwarded (for resampling parameters)
- **Headers**: None
- **Cookies**: None
- **Compression**: Enabled
- **Methods**: GET, HEAD, OPTIONS

Optimized for static tile content that changes infrequently.

### 2. API Cache Behavior (`/api/*`)
- **TTL**: 0 (no caching)
- **Query Strings**: All forwarded
- **Headers**: Authorization, Host
- **Cookies**: All forwarded
- **Compression**: Enabled
- **Methods**: All HTTP methods

Passes through all requests to the origin without caching.

### 3. Default Cache Behavior
- **TTL**: 0 (no caching)
- **Query Strings**: All forwarded
- **Headers**: Authorization, Host
- **Cookies**: All forwarded
- **Compression**: Enabled
- **Methods**: All HTTP methods

Handles `/metrics` and other paths without caching.

## Origin Configuration

### ALB Origin
- **Protocol**: HTTPS only
- **SSL Protocols**: TLSv1.2
- **Connection**: Direct to ALB DNS name
- **Timeout**: Default CloudFront timeouts

## SSL/TLS Configuration

### Default Certificate
When no custom certificate is provided:
- Uses CloudFront default certificate
- Domain: `*.cloudfront.net`
- Protocol: TLSv1

### Custom Certificate
When ACM certificate ARN is provided:
- Uses custom ACM certificate
- SNI-only SSL support
- Minimum protocol: TLSv1.2_2021
- Requires certificate in us-east-1 region

## Usage

### Basic Usage (Default Certificate)
```hcl
module "cloudfront" {
  source = "./modules/cloudfront"
  
  name         = "raster-platform"
  alb_dns_name = module.ecs.alb_dns_name
  price_class  = "PriceClass_100"
  
  tags = {
    project_owner = "platform-team"
    project_title = "raster-platform"
    environment   = "production"
  }
}
```

### Custom Domain with Certificate
```hcl
module "cloudfront" {
  source = "./modules/cloudfront"
  
  name            = "raster-platform"
  alb_dns_name    = module.ecs.alb_dns_name
  certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
  domain_name     = "tiles.example.com"
  price_class     = "PriceClass_All"
  
  tags = {
    project_owner = "platform-team"
    project_title = "raster-platform"
    environment   = "production"
  }
}
```

### With WAF Protection
```hcl
module "cloudfront" {
  source = "./modules/cloudfront"
  
  name         = "raster-platform"
  alb_dns_name = module.ecs.alb_dns_name
  waf_acl_id   = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/example/abc-123"
  
  tags = {
    project_owner = "platform-team"
    project_title = "raster-platform"
    environment   = "production"
  }
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for CloudFront resources | string | - | yes |
| alb_dns_name | DNS name of the ALB origin | string | - | yes |
| certificate_arn | ARN of ACM certificate (must be in us-east-1) | string | "" | no |
| domain_name | Custom domain name for distribution | string | "" | no |
| waf_acl_id | ID of WAF Web ACL to associate | string | "" | no |
| price_class | CloudFront price class | string | PriceClass_100 | no |
| tags | Tags to apply to resources | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| distribution_id | ID of the CloudFront distribution |
| distribution_arn | ARN of the CloudFront distribution |
| distribution_domain_name | Domain name of the distribution |
| distribution_hosted_zone_id | Route 53 zone ID for CloudFront |

## Price Classes

CloudFront offers three price classes:

| Price Class | Edge Locations | Use Case |
|-------------|----------------|----------|
| PriceClass_100 | US, Canada, Europe | Cost-optimized |
| PriceClass_200 | Above + Asia, Africa, Middle East | Balanced |
| PriceClass_All | All edge locations | Best performance |

## Performance Optimization

### Cache Hit Ratio
Maximize cache hits by:
- Using consistent query string parameters
- Avoiding unnecessary headers/cookies
- Setting appropriate TTLs

### Compression
CloudFront automatically compresses:
- Text files (HTML, CSS, JS)
- JSON responses
- SVG images

### Regional Edge Caches
CloudFront uses regional edge caches for:
- Less frequently accessed content
- Reduced origin load
- Improved cache hit ratio

## Security Features

### HTTPS Enforcement
All HTTP requests are automatically redirected to HTTPS with `redirect-to-https` viewer protocol policy.

### Origin Protocol
Origin communication uses HTTPS only, ensuring end-to-end encryption.

### WAF Integration
Optional WAF Web ACL provides:
- Rate limiting
- IP blocking
- SQL injection protection
- XSS protection

### Geo Restrictions
Currently set to "none" but can be configured to allow/deny specific countries.

## Monitoring

### CloudWatch Metrics
CloudFront publishes metrics for:
- Requests
- Bytes downloaded
- Bytes uploaded
- 4xx/5xx error rates
- Cache hit rate

### Access Logs
Optional S3 access logs can be enabled for:
- Request analysis
- Security auditing
- Performance optimization

## Custom Domain Setup

To use a custom domain:

1. Create ACM certificate in **us-east-1** region
2. Validate certificate ownership
3. Provide certificate ARN and domain name to module
4. Create Route 53 alias record pointing to CloudFront distribution

Example Route 53 record:
```hcl
resource "aws_route53_record" "cloudfront" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "tiles.example.com"
  type    = "A"
  
  alias {
    name                   = module.cloudfront.distribution_domain_name
    zone_id                = module.cloudfront.distribution_hosted_zone_id
    evaluate_target_health = false
  }
}
```

## Requirements

- Requirements 3.1: CloudFront with ALB origin
- Requirements 3.2: Tile caching with 24-hour TTL
- Requirements 3.3: API requests without caching
- Requirements 3.4: HTTPS enforcement
- Requirements 3.5: Custom domain and certificate support
- Requirements 6.1: WAF association
- Requirements 9.6: Resource tagging

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.22.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudfront_distribution.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution) | resource |
| [aws_cloudfront_function.spa_routing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_function) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alb_dns_name"></a> [alb\_dns\_name](#input\_alb\_dns\_name) | DNS name of the Application Load Balancer to use as origin | `string` | n/a | yes |
| <a name="input_certificate_arn"></a> [certificate\_arn](#input\_certificate\_arn) | ARN of ACM certificate for custom domain (optional) | `string` | `""` | no |
| <a name="input_cloudfront_oai_path"></a> [cloudfront\_oai\_path](#input\_cloudfront\_oai\_path) | CloudFront Origin Access Identity path | `string` | n/a | yes |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Custom domain name for CloudFront distribution (optional) | `string` | `""` | no |
| <a name="input_price_class"></a> [price\_class](#input\_price\_class) | CloudFront price class (PriceClass\_All, PriceClass\_200, PriceClass\_100) | `string` | `"PriceClass_100"` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Name prefix for CloudFront resources | `string` | n/a | yes |
| <a name="input_s3_bucket_regional_domain_name"></a> [s3\_bucket\_regional\_domain\_name](#input\_s3\_bucket\_regional\_domain\_name) | Regional domain name of S3 bucket for frontend | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_waf_acl_id"></a> [waf\_acl\_id](#input\_waf\_acl\_id) | ID of WAF Web ACL to associate with distribution (optional) | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_distribution_arn"></a> [distribution\_arn](#output\_distribution\_arn) | ARN of the CloudFront distribution |
| <a name="output_distribution_domain_name"></a> [distribution\_domain\_name](#output\_distribution\_domain\_name) | Domain name of the CloudFront distribution |
| <a name="output_distribution_hosted_zone_id"></a> [distribution\_hosted\_zone\_id](#output\_distribution\_hosted\_zone\_id) | CloudFront Route 53 zone ID |
| <a name="output_distribution_id"></a> [distribution\_id](#output\_distribution\_id) | ID of the CloudFront distribution |
<!-- END_TF_DOCS -->