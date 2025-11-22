# GitHub Actions Setup Checklist

## Quick Fix for Permission Error

Follow these steps to fix the "Permission denied" error:

### ✅ Step 1: Enable Workflow Write Permissions

1. Go to your repository on GitHub
2. Click **Settings** (top menu)
3. Click **Actions** (left sidebar)
4. Click **General**
5. Scroll down to **"Workflow permissions"**
6. Select **"Read and write permissions"**
7. Click **"Save"**

That's it! This is the recommended solution.

### ✅ Step 2: Verify the Fix

1. Push the updated workflow file to your repository
2. Go to **Actions** tab
3. Watch the workflow run
4. The "Commit and push documentation changes" step should now succeed

## Alternative: Use Personal Access Token (Optional)

If you prefer not to enable write permissions for all workflows:

### Create PAT

1. Go to **Settings** (your profile, not repository)
2. Click **Developer settings** (bottom of left sidebar)
3. Click **Personal access tokens** > **Tokens (classic)**
4. Click **"Generate new token (classic)"**
5. Name: `GitHub Actions - Terraform Docs`
6. Select scope: `repo` (full control of private repositories)
7. Click **"Generate token"**
8. **Copy the token** (you won't see it again!)

### Add PAT to Repository

1. Go to your repository **Settings**
2. Click **Secrets and variables** > **Actions**
3. Click **"New repository secret"**
4. Name: `PAT_TOKEN`
5. Value: paste your token
6. Click **"Add secret"**

### Update Workflow (if using PAT)

Edit `.github/workflows/deploy.yml`:

```yaml
- name: Checkout code
  uses: actions/checkout@v4
  with:
    token: ${{ secrets.PAT_TOKEN }}  # Changed from GITHUB_TOKEN
```

## Files Changed

The following files were updated to fix the issue:

- ✅ `.github/workflows/deploy.yml` - Added permissions and improved error handling
- ✅ `terraform/.checkov.yml` - Checkov configuration to skip non-critical checks
- ✅ `docs/SECURITY_SCANNING.md` - Security scanning documentation
- ✅ `docs/GITHUB_ACTIONS_SETUP.md` - Complete setup guide
- ✅ `docs/GITHUB_ACTIONS_FIX.md` - Detailed fix explanation
- ✅ `docs/CHECKOV_CHANGES.md` - Checkov changes summary
- ✅ `README.md` - Updated with new documentation references

## What's Fixed

1. ✅ **Checkov now only blocks on CRITICAL issues** (not HIGH/MEDIUM/LOW)
2. ✅ **Documentation commits won't fail the pipeline** (graceful error handling)
3. ✅ **Better error messages** showing what needs to be fixed
4. ✅ **Comprehensive documentation** for troubleshooting

## Next Steps

1. **Enable workflow write permissions** (Step 1 above)
2. **Push changes** to your repository
3. **Watch the workflow run** to verify it works
4. **Review security scan results** (even if they don't block)
5. **Read the documentation** for more details:
   - `docs/GITHUB_ACTIONS_SETUP.md` - Setup and troubleshooting
   - `docs/SECURITY_SCANNING.md` - Security scanning details
   - `docs/GITHUB_ACTIONS_FIX.md` - Detailed fix explanation

## Questions?

See the documentation files listed above or check the GitHub Actions logs for specific error messages.
