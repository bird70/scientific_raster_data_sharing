# Git Workflow Guide

## Understanding the Divergent Branches Issue

When GitHub Actions commits documentation changes and you have local commits, your branches diverge. This is normal and easy to fix.

## Quick Fix

When you see "divergent branches" error:

```bash
# Pull with merge strategy
git pull --no-rebase origin main

# Push your changes
git push origin main
```

## Configure Git to Avoid the Prompt

Set your default pull strategy (choose one):

```bash
# Option 1: Merge (recommended for this project)
git config pull.rebase false

# Option 2: Rebase (cleaner history but can be confusing)
git config pull.rebase true

# Option 3: Fast-forward only (fails if branches diverged)
git config pull.ff only
```

**Recommendation:** Use `git config pull.rebase false` (merge strategy) since GitHub Actions will be committing documentation updates.

## Common Scenarios

### Scenario 1: GitHub Actions Committed Documentation

**What happened:**
- GitHub Actions ran and committed Terraform documentation
- You made local changes
- Branches diverged

**Solution:**
```bash
git pull --no-rebase origin main
git push origin main
```

### Scenario 2: Multiple People Working on Same Branch

**What happened:**
- Someone else pushed to `main`
- You have local commits
- Branches diverged

**Solution:**
```bash
git pull --no-rebase origin main
# Resolve any conflicts if they appear
git push origin main
```

### Scenario 3: You Want to Avoid Merge Commits

**What happened:**
- You prefer a linear history
- Want to rebase instead of merge

**Solution:**
```bash
git pull --rebase origin main
# Resolve any conflicts if they appear
git push origin main
```

## Best Practices

### 1. Pull Before You Push

Always pull the latest changes before pushing:

```bash
git pull origin main
git push origin main
```

### 2. Commit Often, Push Regularly

Don't let your local branch get too far ahead:

```bash
# Make changes
git add .
git commit -m "Your message"
git pull origin main
git push origin main
```

### 3. Use Feature Branches for Large Changes

For significant work, use feature branches:

```bash
# Create feature branch
git checkout -b feature/my-feature

# Make changes and commit
git add .
git commit -m "Add feature"

# Push feature branch
git push origin feature/my-feature

# Create pull request on GitHub
# After review, merge via GitHub UI
```

### 4. Handle Conflicts Carefully

If you get merge conflicts:

```bash
# Pull with merge
git pull --no-rebase origin main

# Git will show conflicted files
# Open each file and resolve conflicts
# Look for markers: <<<<<<<, =======, >>>>>>>

# After resolving conflicts
git add .
git commit -m "Resolve merge conflicts"
git push origin main
```

## GitHub Actions and Git

### Why Branches Diverge

The GitHub Actions workflow commits documentation updates:

```yaml
- name: Commit and push documentation changes
  run: |
    git commit -m "docs: update Terraform module documentation [skip ci]"
    git push
```

This creates a commit on the remote that you don't have locally.

### The [skip ci] Tag

Notice the `[skip ci]` in the commit message. This prevents an infinite loop:
- Without it: commit → trigger workflow → commit → trigger workflow → ...
- With it: commit → trigger workflow → commit with [skip ci] → no trigger ✓

### Disabling Auto-Commit (Optional)

If you prefer to update documentation manually:

Edit `.github/workflows/deploy.yml`:

```yaml
- name: Commit and push documentation changes
  if: false  # Disabled
  run: |
    # ... existing code ...
```

## Troubleshooting

### "fatal: Need to specify how to reconcile divergent branches"

**Problem:** Git doesn't know whether to merge or rebase

**Solution:**
```bash
# Set default strategy
git config pull.rebase false

# Then pull
git pull origin main
```

### "Your branch and 'origin/main' have diverged"

**Problem:** Local and remote have different commits

**Solution:**
```bash
# Pull and merge
git pull --no-rebase origin main

# Push
git push origin main
```

### "refusing to merge unrelated histories"

**Problem:** Local and remote have completely different histories

**Solution:**
```bash
# Force merge (use with caution)
git pull origin main --allow-unrelated-histories

# Or start fresh
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git new-directory
```

### "Updates were rejected because the tip of your current branch is behind"

**Problem:** Remote has commits you don't have

**Solution:**
```bash
# Pull first
git pull origin main

# Then push
git push origin main
```

## Git Configuration

### View Current Configuration

```bash
# View pull strategy
git config pull.rebase

# View all git config
git config --list
```

### Set Configuration Globally

To apply settings to all repositories:

```bash
# Set merge as default for all repos
git config --global pull.rebase false

# Set your name and email
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

### Set Configuration Per Repository

To apply settings only to this repository:

```bash
# Set merge as default for this repo only
git config pull.rebase false
```

## Summary

**Quick Commands:**
```bash
# When branches diverge
git pull --no-rebase origin main
git push origin main

# Configure to avoid prompt
git config pull.rebase false

# Check status
git status

# View commit history
git log --oneline --graph --all
```

**Remember:**
- Pull before push
- Commit often
- Use feature branches for big changes
- Don't panic when branches diverge - it's normal!
