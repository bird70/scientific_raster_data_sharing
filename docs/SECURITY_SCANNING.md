# Security Scanning Configuration

## Overview

This project uses [Checkov](https://www.checkov.io/) for infrastructure security scanning. The scanning is integrated into the CI/CD pipeline to catch security issues early.

## Severity Levels

Checkov categorizes security issues into four severity levels:

- **CRITICAL**: Must be fixed immediately - blocks deployment
- **HIGH**: Should be fixed soon - reported but doesn't block deployment
- **MEDIUM**: Should be addressed - reported but doesn't block deployment
- **LOW**: Nice to have - reported but doesn't block deployment

## CI/CD Integration

### Deployment Blocking Policy

The CI/CD pipeline is configured to:

1. ✅ **Allow deployment** if only HIGH, MEDIUM, or LOW severity issues are found
2. ❌ **Block deployment** if CRITICAL severity issues are found

This approach balances security with development velocity, ensuring that truly critical issues are addressed while allowing teams to iterate on less severe findings.

### Skipped Checks

Some Checkov checks are intentionally skipped because they don't apply to our use case or are configured differently by design. These are documented in `terraform/.checkov.yml`.

#### Common Skipped Checks

**HTTP/HTTPS Configuration**
- `CKV_AWS_2`, `CKV_AWS_103`: HTTP listener is intentional for health checks and development
- `CKV_AWS_131`: HTTP to HTTPS redirect not needed as we support both protocols

**Logging and Monitoring**
- `CKV_AWS_91`: ALB access logging (can be enabled for production)
- `CKV_AWS_150`: Load balancer deletion protection (intentionally disabled for easier teardown)

**Storage Configuration**
- `CKV_AWS_18`: S3 access logging (not needed for all buckets)
- `CKV_AWS_21`: S3 versioning (only enabled where needed)
- `CKV_AWS_145`: S3 KMS encryption (using default encryption)

**Database/Cache Configuration**
- `CKV_AWS_29`, `CKV_AWS_31`: Redis encryption (not available for all instance types)
- `CKV_AWS_84`: OpenSearch node-to-node encryption (cost optimization)

**Networking**
- `CKV_AWS_130`: Public IP assignment in public subnets (required for ALB)
- `CKV2_AWS_11`: VPC flow logging (can be enabled for production)

## Running Checkov Locally

### Install Checkov

```bash
pip install checkov
```

### Run Security Scan

```bash
# Run with configuration file (skips non-critical checks)
checkov --directory terraform --config-file terraform/.checkov.yml

# Run without configuration (shows all issues)
checkov --directory terraform --framework terraform

# Run and output to JSON
checkov --directory terraform --output json --output-file-path .
```

### Check Specific Severity

```bash
# Only show CRITICAL issues
checkov --directory terraform --check-severity CRITICAL

# Show CRITICAL and HIGH issues
checkov --directory terraform --check-severity CRITICAL,HIGH
```

## Updating Security Configuration

### Adding New Skip Rules

If you need to skip additional checks, add them to `terraform/.checkov.yml`:

```yaml
skip-check:
  - CKV_AWS_XXX  # Brief explanation of why this is skipped
```

### Changing Severity Threshold

To change what severity levels block deployment, modify the "Check for critical security issues" step in `.github/workflows/deploy.yml`.

## Security Best Practices

1. **Review skipped checks regularly** - Ensure they're still valid for your use case
2. **Address HIGH severity issues** - Even though they don't block deployment, they should be fixed
3. **Run scans locally** - Before pushing code, run Checkov to catch issues early
4. **Document exceptions** - Always document why a check is skipped
5. **Enable production features** - Consider enabling logging, encryption, and monitoring for production environments

## Resources

- [Checkov Documentation](https://www.checkov.io/documentation.html)
- [AWS Security Best Practices](https://docs.aws.amazon.com/security/)
- [Terraform Security Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)
