# Terraform Resource Management: What Happens When You Remove Code

## The Short Answer

**Terraform WILL automatically destroy resources when you remove them from your code.**

When you remove ECS resources from your Terraform and run `terraform apply`, Terraform will:
1. Detect the resources are no longer in your code
2. Show you a plan to **destroy** them
3. Delete them from AWS (if you approve)

**No orphaned resources** - Terraform tracks everything in its state file.

---

## How Terraform Tracks Resources

### The State File

Terraform maintains a `terraform.tfstate` file that tracks:
- What resources exist in AWS
- What resources are defined in your code
- The mapping between them

```
terraform.tfstate contains:
{
  "resources": [
    {
      "type": "aws_ecs_cluster",
      "name": "this",
      "instances": [{
        "attributes": {
          "id": "raster-app-prod-ecs-cluster",
          "arn": "arn:aws:ecs:..."
        }
      }]
    }
  ]
}
```

### What Happens on `terraform apply`

```
1. Terraform reads your .tf files
2. Terraform reads terraform.tfstate
3. Terraform compares them:
   - In code + in state = Keep (maybe update)
   - In code + not in state = Create
   - Not in code + in state = DESTROY ⚠️
4. Shows you the plan
5. Waits for your approval
6. Executes the changes
```

---

## Example: Removing ECS Resources

### Current Terraform Code

```hcl
# main.tf
module "ecs" {
  source = "./modules/ecs"
  # ... configuration
}
```

This creates:
- ECS Cluster
- ECS Services (tiles, timeseries, dask)
- ECS Task Definitions
- ALB
- Target Groups
- Auto-scaling policies
- CloudWatch log groups

### After Removing ECS Module

```hcl
# main.tf
# module "ecs" {  ← Commented out or deleted
#   source = "./modules/ecs"
# }

# Add Lambda instead
module "lambda_api" {
  source = "./modules/lambda"
  # ... configuration
}
```

### What `terraform plan` Shows

```bash
$ terraform plan

Terraform will perform the following actions:

  # module.ecs.aws_ecs_cluster.this will be destroyed
  - resource "aws_ecs_cluster" "this" {
      - id   = "raster-app-prod-ecs-cluster"
      - name = "raster-app-prod-ecs-cluster"
    }

  # module.ecs.aws_ecs_service.tiles will be destroyed
  - resource "aws_ecs_service" "tiles" {
      - id   = "arn:aws:ecs:..."
      - name = "tiles-service"
    }

  # module.ecs.aws_ecs_service.timeseries will be destroyed
  - resource "aws_ecs_service" "timeseries" {
      - id   = "arn:aws:ecs:..."
      - name = "timeseries-service"
    }

  # ... (shows ALL resources that will be destroyed)

  # module.lambda_api.aws_lambda_function.api will be created
  + resource "aws_lambda_function" "api" {
      + function_name = "raster-app-api"
      + runtime       = "python3.12"
    }

Plan: 1 to add, 0 to change, 15 to destroy.
```

**Terraform explicitly tells you what will be destroyed!**

### After `terraform apply`

```bash
$ terraform apply

# Shows the same plan
# Asks for confirmation:

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

# Then destroys resources:
module.ecs.aws_ecs_service.tiles: Destroying...
module.ecs.aws_ecs_service.timeseries: Destroying...
module.ecs.aws_ecs_cluster.this: Destroying...
# ...

# And creates new ones:
module.lambda_api.aws_lambda_function.api: Creating...

Apply complete! Resources: 1 added, 0 changed, 15 destroyed.
```

**All ECS resources are completely removed from AWS.**

---

## Important Scenarios

### Scenario 1: Gradual Migration (Recommended)

**Problem:** You want to test Lambda before removing ECS

**Solution:** Keep both temporarily

```hcl
# main.tf

# Keep ECS running (for now)
module "ecs" {
  source = "./modules/ecs"
  # ... existing config
}

# Add Lambda alongside
module "lambda_api" {
  source = "./modules/lambda"
  # ... new config
}
```

**Result:**
- Both ECS and Lambda exist
- You can test Lambda
- Switch traffic gradually
- Remove ECS when confident

### Scenario 2: Accidental Deletion Protection

**Problem:** You don't want to accidentally destroy critical resources

**Solution:** Use `prevent_destroy` lifecycle rule

```hcl
resource "aws_s3_bucket" "critical_data" {
  bucket = "my-critical-data"

  lifecycle {
    prevent_destroy = true  # Terraform will refuse to destroy this
  }
}
```

**Result:**
```bash
$ terraform apply
Error: Instance cannot be destroyed

  on main.tf line 10:
  10: resource "aws_s3_bucket" "critical_data" {

Resource has lifecycle.prevent_destroy set, but the plan calls for
this resource to be destroyed.
```

### Scenario 3: Removing a Module

**Problem:** You remove an entire module from `main.tf`

**What happens:**
```hcl
# Before
module "data" {
  source = "./modules/data"
}

# After - module removed
# (nothing here)
```

**Result:**
- ALL resources in that module will be destroyed
- OpenSearch, Redis, S3 buckets, etc.
- Terraform shows you the full list
- You must approve

### Scenario 4: Renaming a Resource

**Problem:** You rename a resource in Terraform

```hcl
# Before
resource "aws_ecs_cluster" "this" {
  name = "my-cluster"
}

# After
resource "aws_ecs_cluster" "main" {  # Renamed from "this" to "main"
  name = "my-cluster"
}
```

**What Terraform sees:**
- `aws_ecs_cluster.this` no longer in code → DESTROY
- `aws_ecs_cluster.main` not in state → CREATE

**Result:** Terraform will destroy and recreate! (Downtime!)

**Solution:** Use `terraform state mv`

```bash
# Tell Terraform the resource was renamed, not replaced
terraform state mv 'aws_ecs_cluster.this' 'aws_ecs_cluster.main'
```

---

## Safe Migration Strategy

### Step 1: Review Current State

```bash
# See what Terraform is currently managing
terraform state list

# Output:
module.ecs.aws_ecs_cluster.this
module.ecs.aws_ecs_service.tiles
module.ecs.aws_ecs_service.timeseries
module.ecs.aws_lb.alb
# ... etc
```

### Step 2: Plan the Change

```bash
# See what would happen (don't apply yet!)
terraform plan -out=migration.tfplan

# Review carefully:
# - What will be destroyed?
# - What will be created?
# - Any unexpected changes?
```

### Step 3: Backup State

```bash
# Backup your state file before major changes
cp terraform.tfstate terraform.tfstate.backup.$(date +%Y%m%d)
```

### Step 4: Apply in Stages

**Stage 1: Add new resources (Lambda)**
```hcl
# Keep ECS
module "ecs" { ... }

# Add Lambda
module "lambda_api" { ... }
```

```bash
terraform apply  # Only creates Lambda, doesn't destroy ECS
```

**Stage 2: Test new resources**
- Verify Lambda works
- Test API endpoints
- Check logs

**Stage 3: Remove old resources (ECS)**
```hcl
# Remove ECS
# module "ecs" { ... }  ← Commented out

# Keep Lambda
module "lambda_api" { ... }
```

```bash
terraform plan  # Review what will be destroyed
terraform apply # Destroy ECS resources
```

---

## What About Data?

### S3 Buckets

**By default:** Terraform will try to delete S3 buckets

**Problem:** If bucket has data, deletion fails

```bash
Error: error deleting S3 Bucket (my-bucket): BucketNotEmpty
```

**Solution 1:** Empty bucket first
```bash
aws s3 rm s3://my-bucket --recursive
terraform apply
```

**Solution 2:** Use `force_destroy`
```hcl
resource "aws_s3_bucket" "data" {
  bucket        = "my-data"
  force_destroy = true  # Allows deletion even with contents
}
```

**Solution 3:** Remove from Terraform but keep in AWS
```bash
# Remove from Terraform state without deleting from AWS
terraform state rm aws_s3_bucket.data
```

### Databases (RDS, OpenSearch)

**By default:** Terraform will delete databases

**Problem:** You lose all data!

**Solution:** Use `skip_final_snapshot = false`
```hcl
resource "aws_db_instance" "postgres" {
  # ...
  skip_final_snapshot       = false
  final_snapshot_identifier = "my-db-final-snapshot"
}
```

**Result:** Terraform creates a snapshot before deletion

---

## Common Mistakes

### Mistake 1: Deleting State File

```bash
# DON'T DO THIS!
rm terraform.tfstate
```

**Result:**
- Terraform forgets about all resources
- Resources still exist in AWS
- Terraform can't manage them anymore
- You have orphaned resources!

**Fix:** Restore from backup or manually import resources

### Mistake 2: Editing State File Manually

```bash
# DON'T DO THIS!
vim terraform.tfstate  # Manual edits
```

**Result:** State corruption, unpredictable behavior

**Fix:** Use `terraform state` commands instead

### Mistake 3: Not Reviewing Plan

```bash
# DON'T DO THIS!
terraform apply -auto-approve  # Skips review!
```

**Result:** Accidental deletions

**Fix:** Always review `terraform plan` first

---

## Terraform State Commands

### View State

```bash
# List all resources
terraform state list

# Show details of a resource
terraform state show aws_ecs_cluster.this
```

### Move Resources

```bash
# Rename a resource
terraform state mv 'aws_ecs_cluster.this' 'aws_ecs_cluster.main'

# Move to a module
terraform state mv 'aws_lambda_function.api' 'module.lambda.aws_lambda_function.api'
```

### Remove from State (Keep in AWS)

```bash
# Remove from Terraform management without deleting from AWS
terraform state rm aws_s3_bucket.keep_this

# Now Terraform won't touch this resource
# It still exists in AWS, just not managed by Terraform
```

### Import Existing Resources

```bash
# Add existing AWS resource to Terraform
terraform import aws_ecs_cluster.this raster-app-prod-ecs-cluster
```

---

## Migration Checklist

Before removing resources:

- [ ] Review `terraform plan` output carefully
- [ ] Backup `terraform.tfstate`
- [ ] Identify critical data (S3, databases)
- [ ] Plan data migration if needed
- [ ] Test new resources before removing old ones
- [ ] Have rollback plan ready
- [ ] Schedule during maintenance window
- [ ] Monitor after changes

---

## Example: Your ECS to Lambda Migration

### Safe Approach

**Week 1: Add Lambda**
```hcl
module "ecs" { ... }      # Keep
module "lambda_api" { ... } # Add
```
```bash
terraform apply  # Creates Lambda, keeps ECS
```

**Week 2: Test & Switch Traffic**
- Test Lambda endpoints
- Update DNS/ALB to point to Lambda
- Monitor performance

**Week 3: Remove ECS**
```hcl
# module "ecs" { ... }    # Remove
module "lambda_api" { ... } # Keep
```
```bash
terraform plan   # Review destruction
terraform apply  # Destroy ECS
```

**Result:** Zero downtime, safe migration

---

## The Bottom Line

**Terraform is declarative:**
- Your code = desired state
- Terraform makes AWS match your code
- Remove from code = remove from AWS
- **No orphaned resources** (unless you use `terraform state rm`)

**Always:**
1. Review `terraform plan` before applying
2. Backup state before major changes
3. Test new resources before removing old ones
4. Use `prevent_destroy` for critical resources

**Terraform won't surprise you** - it always shows you exactly what it will do before doing it!
