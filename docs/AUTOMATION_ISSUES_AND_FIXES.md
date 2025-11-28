# Automation Issues and Fixes

## Root Cause Analysis

Your infrastructure has **3 critical issues** preventing full automation:

### Issue 1: ECS Services Depend on HTTPS Listener (BLOCKING)
**Location**: `terraform/modules/ecs/main.tf` lines 617, 641

```terraform
resource "aws_ecs_service" "tiles" {
  # ...
  depends_on = [aws_lb_listener.https]  # ❌ BLOCKS when certificate is PLACEHOLDER
}

resource "aws_ecs_service" "timeseries" {
  # ...
  depends_on = [aws_lb_listener.https]  # ❌ BLOCKS when certificate is PLACEHOLDER
}
```

**Problem**: 
- HTTPS listener is conditional (only created if valid certificate exists)
- ECS services have hard dependency on HTTPS listener
- When certificate is PLACEHOLDER, HTTPS listener doesn't exist
- ECS services fail to create because dependency doesn't exist
- **Result**: Application never starts, even though HTTP works fine

**Impact**: CI/CD pipeline cannot deploy application without valid certificate

---

### Issue 2: CloudFront Requires Valid Certificate (BLOCKING)
**Location**: `terraform/modules/cloudfront/main.tf` line 13

```terraform
custom_origin_config {
  origin_protocol_policy = "https-only"  # ❌ Requires HTTPS on ALB
}
```

**Problem**:
- CloudFront tries to connect to ALB via HTTPS
- ALB doesn't have HTTPS listener (certificate is PLACEHOLDER)
- CloudFront creation fails

**Impact**: CloudFront module cannot be deployed without certificate

---

### Issue 3: Certificate Validation is Manual
**Location**: `terraform.tfvars`

```terraform
alb_certificate_arn = "arn:aws:acm:ap-southeast-2:123456789101:certificate/PLACEHOLDER"
```

**Problem**:
- ACM certificate must be manually created in AWS Console
- Certificate must be manually validated via DNS or email
- ARN must be manually copied to terraform.tfvars
- This is a **one-time manual step** that cannot be automated

**Impact**: Initial deployment requires manual intervention

---

## The Fix: Make HTTPS Optional

### Step 1: Fix ECS Service Dependencies

**File**: `terraform/modules/ecs/main.tf`

Change lines 617 and 641 from:
```terraform
depends_on = [aws_lb_listener.https]
```

To:
```terraform
depends_on = [aws_lb_listener.http]
```

**Rationale**: 
- HTTP listener is always created
- ECS services work fine with HTTP-only
- HTTPS can be added later without breaking services

---

### Step 2: Make CloudFront Conditional

**File**: `terraform/main.tf`

Add condition to CloudFront module:
```terraform
module "cloudfront" {
  count  = var.alb_certificate_arn != "" && var.alb_certificate_arn != "arn:aws:acm:ap-southeast-2:123456789101:certificate/PLACEHOLDER" ? 1 : 0
  source = "./modules/cloudfront"
  # ... rest of config
}
```

**Rationale**:
- CloudFront only created when valid certificate exists
- Infrastructure works without CloudFront (ALB handles traffic)
- CloudFront can be added later for CDN benefits

---

### Step 3: Update CloudFront to Support HTTP Fallback

**File**: `terraform/modules/cloudfront/main.tf`

Change line 13:
```terraform
origin_protocol_policy = var.certificate_arn != "" ? "https-only" : "http-only"
```

**Rationale**:
- CloudFront can use HTTP to connect to ALB if no certificate
- Still secure (CloudFront → user is HTTPS, CloudFront → ALB can be HTTP in VPC)

---

## Deployment Workflow

### First-Time Deployment (No Certificate)

```bash
# 1. Set certificate to empty or PLACEHOLDER in terraform.tfvars
alb_certificate_arn = ""

# 2. Deploy infrastructure
terraform apply

# 3. Application works on HTTP
curl http://<alb-dns>/health
```

**Result**: 
- ✅ VPC, subnets, security groups created
- ✅ S3 buckets created
- ✅ OpenSearch created
- ✅ Redis created
- ✅ ALB created with HTTP listener
- ✅ ECS services created and running
- ✅ Ingestion pipeline created
- ❌ HTTPS listener NOT created (expected)
- ❌ CloudFront NOT created (expected)

---

### Adding HTTPS Later (Optional)

```bash
# 1. Create ACM certificate in AWS Console
#    - Request certificate for your domain
#    - Validate via DNS (add CNAME records)
#    - Wait for "Issued" status

# 2. Update terraform.tfvars
alb_certificate_arn = "arn:aws:acm:ap-southeast-2:123456789101:certificate/REAL-CERT-ID"

# 3. Apply changes
terraform apply

# 4. HTTPS now works
curl https://<alb-dns>/health
```

**Result**:
- ✅ HTTPS listener created
- ✅ CloudFront created (if enabled)
- ✅ Existing services continue running
- ✅ Zero downtime upgrade

---

## CI/CD Pipeline Compatibility

### Current State (BROKEN)
```yaml
# GitHub Actions tries to deploy
terraform apply
# ❌ Fails because ECS services depend on non-existent HTTPS listener
# ❌ Application never starts
```

### After Fix (WORKS)
```yaml
# GitHub Actions deploys
terraform apply
# ✅ Infrastructure created
# ✅ ECS services start with HTTP
# ✅ Application accessible via HTTP
# ✅ Docker image deployed automatically
# ✅ Tests pass
```

---

## Manual Steps Required (One-Time Only)

### Before First Deployment

1. **Create terraform.tfvars** (if not exists)
   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   ```

2. **Set required variables**
   ```terraform
   service_owner  = "Your Name"
   project_title  = "cloud-scientific-raster-sharing"
   environment    = "dev"
   
   # Leave empty for HTTP-only deployment
   alb_certificate_arn = ""
   domain_name         = ""
   cognito_user_pool_id = ""
   cognito_client_id    = ""
   ```

3. **Run terraform init**
   ```bash
   cd terraform
   terraform init
   ```

### Optional: Add HTTPS (After Deployment)

1. **Create ACM Certificate** (AWS Console)
   - Certificate Manager → Request certificate
   - Enter domain name
   - Choose DNS validation
   - Add CNAME records to your DNS
   - Wait for "Issued" status

2. **Update terraform.tfvars**
   ```terraform
   alb_certificate_arn = "arn:aws:acm:ap-southeast-2:123456789101:certificate/REAL-ID"
   domain_name         = "your-domain.com"
   ```

3. **Apply changes**
   ```bash
   terraform apply
   ```

---

## Testing the Fixes

### Test 1: Fresh Deployment (No Certificate)
```bash
cd terraform
terraform destroy -auto-approve  # Clean slate
terraform apply -auto-approve

# Verify services are running
aws ecs describe-services \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services tiles-service timeseries-service \
  --query 'services[*].[serviceName,runningCount,desiredCount]'

# Expected: runningCount = desiredCount for both services
```

### Test 2: Application Responds
```bash
ALB_DNS=$(terraform output -raw alb_dns_name)
curl http://$ALB_DNS/health

# Expected: {"status":"ok"}
```

### Test 3: Add HTTPS (After Certificate Created)
```bash
# Update terraform.tfvars with real certificate ARN
terraform apply

# Verify HTTPS works
curl https://$ALB_DNS/health

# Expected: {"status":"ok"}
```

---

## Summary of Changes Needed

| File | Line | Change | Reason |
|------|------|--------|--------|
| `terraform/modules/ecs/main.tf` | 617 | `depends_on = [aws_lb_listener.http]` | Remove HTTPS dependency |
| `terraform/modules/ecs/main.tf` | 641 | `depends_on = [aws_lb_listener.http]` | Remove HTTPS dependency |
| `terraform/main.tf` | CloudFront module | Add `count` condition | Make CloudFront optional |
| `terraform/modules/cloudfront/main.tf` | 13 | Add HTTP fallback | Support HTTP origins |

---

## Impact on Existing Deployment

If you already have infrastructure deployed:

1. **Apply these fixes**
   ```bash
   terraform apply
   ```

2. **No downtime** - Changes are non-destructive:
   - ECS services will update dependency (no restart)
   - CloudFront condition evaluated (no change if already exists)

3. **Services continue running** - No interruption to running tasks

---

## Long-Term Automation Strategy

### Phase 1: HTTP-Only (Fully Automated) ✅
- Terraform creates all infrastructure
- GitHub Actions deploys Docker images
- Application runs on HTTP
- No manual steps after initial terraform.tfvars setup

### Phase 2: HTTPS (One Manual Step) ⚠️
- Create ACM certificate (manual, one-time)
- Update terraform.tfvars with certificate ARN
- Terraform apply adds HTTPS
- Future deployments fully automated

### Phase 3: Full Automation (Advanced) 🚀
- Use Terraform to create ACM certificate
- Use Terraform to create Route53 DNS records
- Fully automated HTTPS setup
- Requires: Domain managed in Route53

---

## Conclusion

**Root Cause**: Hard dependency on HTTPS listener that doesn't exist when certificate is PLACEHOLDER

**Solution**: Make HTTPS optional, use HTTP as baseline

**Result**: 
- ✅ Infrastructure deploys successfully without certificate
- ✅ Application runs on HTTP immediately
- ✅ CI/CD pipeline works end-to-end
- ✅ HTTPS can be added later without breaking anything
- ✅ Zero manual steps after initial terraform.tfvars setup

**Trade-off**: HTTP-only until certificate is manually created (acceptable for dev/test environments)
