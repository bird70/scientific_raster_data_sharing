# Checkov Security Scanning Changes

## Summary

Updated the CI/CD pipeline to make Checkov security scanning more practical by only blocking deployments on **CRITICAL** severity issues, while still reporting HIGH, MEDIUM, and LOW severity findings.

## What Changed

### 1. Updated GitHub Actions Workflow (`.github/workflows/deploy.yml`)

**Before:**
- Checkov would fail on any security issue
- No severity filtering
- Blocked deployments unnecessarily

**After:**
- Only CRITICAL severity issues block deployment
- HIGH, MEDIUM, and LOW issues are reported but don't block
- Better error messages showing what needs to be fixed

### 2. Created Checkov Configuration (`.checkov.yml`)

Added a configuration file that skips checks that are:
- Not applicable to our use case
- Intentionally configured differently
- Cost-optimization trade-offs

**Examples of skipped checks:**
- HTTP listener (needed for health checks)
- S3 access logging (not needed for all buckets)
- Redis encryption (not available for all instance types)
- VPC flow logging (can enable for production)

### 3. Added Documentation (`docs/SECURITY_SCANNING.md`)

Comprehensive guide covering:
- Severity levels and what they mean
- CI/CD integration and blocking policy
- List of skipped checks with explanations
- How to run Checkov locally
- Security best practices

## How It Works Now

### CI/CD Pipeline Flow

```
1. Run Checkov scan with configuration
   ↓
2. Generate JSON report
   ↓
3. Count CRITICAL and HIGH severity issues
   ↓
4. If CRITICAL issues found → ❌ Block deployment
   ↓
5. If only HIGH/MEDIUM/LOW → ⚠️ Report but allow deployment
   ↓
6. Continue with deployment
```

### Example Output

**No Critical Issues (Deployment Proceeds):**
```
📊 Security Scan Summary:
  - Critical severity issues: 0
  - High severity issues: 3
  - Total critical/high: 3

⚠️  HIGH severity issues found (not blocking deployment):
  - [CKV_AWS_91] Ensure the ELBv2 has access logging enabled
  - [CKV_AWS_150] Ensure Load Balancer has deletion protection
  - [CKV2_AWS_11] Ensure VPC flow logging is enabled

✅ No critical security issues found - deployment can proceed
```

**Critical Issues Found (Deployment Blocked):**
```
📊 Security Scan Summary:
  - Critical severity issues: 2
  - High severity issues: 1
  - Total critical/high: 3

❌ CRITICAL severity security issues found!
The following critical issues must be addressed:
  - [CKV_AWS_XXX] Security group allows unrestricted access
  - [CKV_AWS_YYY] IAM policy allows full admin access
```

## Benefits

1. **Faster Iteration**: Don't get blocked by non-critical findings
2. **Better Security**: Still catch and report all issues
3. **Clear Priorities**: Know what must be fixed vs. what should be fixed
4. **Documented Exceptions**: All skipped checks are documented with reasons
5. **Flexible**: Easy to adjust severity threshold or skip rules

## Running Locally

Before pushing code, run Checkov locally to catch issues:

```bash
# Install Checkov
pip install checkov

# Run with project configuration
cd terraform
checkov --directory . --config-file .checkov.yml

# Or run without config to see all issues
checkov --directory .
```

## Adjusting Configuration

### To Skip Additional Checks

Edit `terraform/.checkov.yml`:

```yaml
skip-check:
  - CKV_AWS_XXX  # Brief explanation
```

### To Change Severity Threshold

Edit `.github/workflows/deploy.yml` in the "Check for critical security issues" step:

```bash
# Current: Only CRITICAL blocks deployment
if [ "$CRITICAL_COUNT" -gt 0 ]; then
  exit 1
fi

# To also block on HIGH:
TOTAL_CRITICAL=$(($CRITICAL_COUNT + $HIGH_COUNT))
if [ "$TOTAL_CRITICAL" -gt 0 ]; then
  exit 1
fi
```

## Files Modified

- `.github/workflows/deploy.yml` - Updated Checkov steps
- `terraform/.checkov.yml` - New configuration file
- `docs/SECURITY_SCANNING.md` - New documentation
- `docs/CHECKOV_CHANGES.md` - This file
- `README.md` - Added reference to security docs

## Next Steps

1. Review the skipped checks in `.checkov.yml` and adjust as needed
2. Address HIGH severity issues when time permits
3. Consider enabling additional security features for production:
   - ALB access logging
   - VPC flow logs
   - S3 access logging
   - Load balancer deletion protection

## Questions?

See `docs/SECURITY_SCANNING.md` for detailed information or check the [Checkov documentation](https://www.checkov.io/).
