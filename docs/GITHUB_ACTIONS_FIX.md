# GitHub Actions Permission Fix

## Problem

The GitHub Actions workflow was failing with a permission error when trying to commit and push documentation changes:

```
remote: Permission to bird70/scientific_raster_data_sharing.git denied to github-actions[bot].
fatal: unable to access 'https://github.com/...': The requested URL returned error: 403
Error: Process completed with exit code 128.
```

## Root Cause

By default, the `GITHUB_TOKEN` provided to workflows has read-only permissions. When the workflow tried to push commits, it was denied access.

## Solution Applied

### 1. Added Workflow Permissions

Updated `.github/workflows/deploy.yml` to explicitly grant write permissions to the `terraform-docs-security` job:

```yaml
terraform-docs-security:
  name: Terraform Documentation and Security
  runs-on: ubuntu-latest
  needs: test
  permissions:
    contents: write      # Allow writing to repository
    pull-requests: write # Allow creating/updating PRs
```

### 2. Improved Checkout Configuration

Added `persist-credentials: true` to ensure credentials are available for git operations:

```yaml
- name: Checkout code
  uses: actions/checkout@v4
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    persist-credentials: true
```

### 3. Made Commit Step More Robust

Updated the commit and push step to:
- Use the correct GitHub Actions bot email
- Handle failures gracefully
- Continue even if push fails (non-critical operation)

```yaml
- name: Commit and push documentation changes
  run: |
    git config --local user.email "41898282+github-actions[bot]@users.noreply.github.com"
    git config --local user.name "github-actions[bot]"
    git add terraform/**/README.md || true
    
    if git diff --staged --quiet; then
      echo "✅ No documentation changes to commit"
    else
      echo "📝 Committing documentation changes..."
      git commit -m "docs: update Terraform module documentation [skip ci]"
      
      echo "⬆️ Pushing changes..."
      git push || {
        echo "⚠️ Failed to push documentation changes"
        echo "This is not critical - documentation can be updated manually"
        exit 0
      }
      echo "✅ Documentation updated successfully"
    fi
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
  continue-on-error: true
```

## Additional Configuration Required

### Option 1: Enable Workflow Write Permissions (Recommended)

Go to your repository settings and enable write permissions:

1. Navigate to **Settings > Actions > General**
2. Scroll to "Workflow permissions"
3. Select **"Read and write permissions"**
4. Click **"Save"**

This is the simplest solution and works for most use cases.

### Option 2: Use Personal Access Token (Alternative)

If you prefer more control or need to work across repositories:

1. Create a Personal Access Token (PAT):
   - Go to **Settings > Developer settings > Personal access tokens > Tokens (classic)**
   - Click "Generate new token (classic)"
   - Give it a descriptive name (e.g., "GitHub Actions - Terraform Docs")
   - Select the `repo` scope
   - Click "Generate token"
   - Copy the token (you won't see it again!)

2. Add the token as a repository secret:
   - Go to your repository **Settings > Secrets and variables > Actions**
   - Click "New repository secret"
   - Name: `PAT_TOKEN`
   - Value: paste your token
   - Click "Add secret"

3. Update the workflow to use the PAT:
   ```yaml
   - name: Checkout code
     uses: actions/checkout@v4
     with:
       token: ${{ secrets.PAT_TOKEN }}
   ```

### Option 3: Disable Auto-Commit (If Not Needed)

If you don't need automatic documentation updates, you can disable the commit step:

```yaml
- name: Commit and push documentation changes
  if: false  # Disabled
  run: |
    # ... existing code ...
```

## Verification

After applying the fix, the workflow should:

1. ✅ Run Checkov security scan successfully
2. ✅ Generate Terraform documentation
3. ✅ Commit and push changes (if permissions are configured)
4. ✅ Continue to deployment even if commit fails

## Related Documentation

- `docs/GITHUB_ACTIONS_SETUP.md` - Complete GitHub Actions setup guide
- `docs/SECURITY_SCANNING.md` - Checkov configuration details
- `.github/workflows/deploy.yml` - The workflow file

## Testing the Fix

To test if the fix works:

1. Make a small change to a Terraform file
2. Commit and push to `main` branch
3. Watch the GitHub Actions workflow run
4. Check if the "Commit and push documentation changes" step succeeds
5. Verify that documentation was updated in the repository

## Troubleshooting

### Still Getting Permission Errors?

1. **Check workflow permissions**:
   - Go to Settings > Actions > General
   - Verify "Read and write permissions" is selected

2. **Check branch protection rules**:
   - Go to Settings > Branches
   - If `main` is protected, ensure "Allow GitHub Actions to bypass branch protection" is enabled

3. **Try using a PAT**:
   - Follow Option 2 above to use a Personal Access Token

### Commits Not Appearing?

1. **Check if there are changes**:
   - The workflow only commits if documentation actually changed

2. **Check the workflow logs**:
   - Look for "No documentation changes to commit" message

3. **Verify [skip ci] is working**:
   - The commit message includes `[skip ci]` to prevent infinite loops

## Summary

The fix adds proper permissions to the GitHub Actions workflow and makes the commit step more robust. You need to either:
- Enable "Read and write permissions" in repository settings (recommended), OR
- Use a Personal Access Token

The workflow will now successfully commit documentation changes without failing the entire pipeline.
