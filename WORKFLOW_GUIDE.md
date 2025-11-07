# 🤖 Automatic Deployment Workflow Guide

## Overview

Your trading photo gallery now has **automatic deployment** to GitHub Pages! Every time you push changes to photos or the gallery page, your site updates automatically.

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│  1. You add photos locally                                  │
│     ./add-photo.sh screenshot.png                           │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  2. You commit and push to GitHub                           │
│     git add photos/                                         │
│     git commit -m "Add photos"                              │
│     git push                                                │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  3. GitHub Actions detects changes                          │
│     ✓ Changes in photos/ folder detected                   │
│     ✓ Workflow automatically triggered                      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  4. Workflow builds and deploys                             │
│     → Checkout your code                                    │
│     → Configure GitHub Pages                                │
│     → Upload site files                                     │
│     → Deploy to GitHub Pages                                │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  5. Your site is live! (30-60 seconds)                      │
│     https://YOUR_USERNAME.github.io/dt-records/             │
└─────────────────────────────────────────────────────────────┘
```

## Workflow Triggers

The workflow automatically runs when you push changes to:

### ✅ Photos Directory
```bash
photos/
├── 2025-11-07/
│   └── screenshot.png  ← Changes here trigger deployment
```

### ✅ Gallery Page
```bash
index.html  ← Changes here trigger deployment
```

### ✅ Workflow File
```bash
.github/workflows/deploy.yml  ← Updates to workflow trigger deployment
```

## Manual Deployment

You can also trigger deployment manually:

1. Go to your repository on GitHub
2. Click **"Actions"** tab
3. Select **"Deploy to GitHub Pages"** workflow
4. Click **"Run workflow"** dropdown
5. Click **"Run workflow"** button

## Monitoring Deployments

### View Deployment Status

**Option 1: GitHub Actions Tab**
1. Go to your repository
2. Click **"Actions"** tab
3. See all workflow runs with status (✓ success, ✗ failed, ⟳ in progress)

**Option 2: Repository Badge** (Optional)
Add this to your README to show deployment status:
```markdown
![Deploy Status](https://github.com/YOUR_USERNAME/dt-records/actions/workflows/deploy.yml/badge.svg)
```

**Option 3: Commit History**
- Green checkmark ✓ = Deployed successfully
- Red X ✗ = Deployment failed
- Yellow circle ⟳ = Deployment in progress

## Workflow Configuration

The workflow is defined in `.github/workflows/deploy.yml`:

### Key Features:
- **Automatic triggering** on relevant file changes
- **Manual trigger** option for on-demand deployment
- **Concurrent deployment control** (no conflicting deployments)
- **Proper permissions** for GitHub Pages deployment
- **Fast deployment** using GitHub's official actions

### Workflow Permissions:
```yaml
permissions:
  contents: read      # Read repository files
  pages: write        # Write to GitHub Pages
  id-token: write     # Authentication token
```

## Typical Workflow Usage

### Daily Photo Upload:
```bash
# Monday trading session
./add-photo.sh ~/Screenshots/trade-1.png
./add-photo.sh ~/Screenshots/trade-2.png

# Commit and push (triggers auto-deploy)
git add photos/
git commit -m "Add Monday trading screenshots"
git push

# Wait 30-60 seconds
# Visit: https://YOUR_USERNAME.github.io/dt-records/
# Your new photos are live! ✨
```

### Update Gallery Design:
```bash
# Edit the gallery
nano index.html

# Commit and push (triggers auto-deploy)
git add index.html
git commit -m "Update gallery styling"
git push

# Site updates automatically!
```

## Benefits of This Setup

✅ **Zero manual deployment** - Push and forget!  
✅ **Fast updates** - Live in under a minute  
✅ **Automatic only when needed** - Workflow only runs for relevant changes  
✅ **Error detection** - See if deployment fails in Actions tab  
✅ **Version control** - Every deployment is tied to a git commit  
✅ **Rollback capability** - Easy to revert to previous version  

## Troubleshooting

### Workflow not triggering?
```bash
# Check if you're on the main branch
git branch

# Check if you pushed to main
git status
git log --oneline -n 5
```

### Deployment failing?
1. Go to **Actions** tab on GitHub
2. Click the failed workflow run
3. Expand failed steps to see error messages
4. Common issues:
   - Pages not enabled (Settings → Pages → Source: GitHub Actions)
   - Repository permissions (Settings → Actions → General)
   - Syntax errors in workflow file

### Changes not showing up?
- Wait full 60 seconds (deployment takes time)
- Hard refresh browser: `Ctrl+Shift+R` (Windows/Linux) or `Cmd+Shift+R` (Mac)
- Clear browser cache
- Check Actions tab to verify deployment completed

### Want to disable auto-deployment?
```bash
# Rename the workflow file to disable it
git mv .github/workflows/deploy.yml .github/workflows/deploy.yml.disabled
git commit -m "Disable auto-deployment"
git push
```

## Advanced: Customizing the Workflow

Want to customize when deployment happens? Edit `.github/workflows/deploy.yml`:

### Deploy on all changes:
```yaml
on:
  push:
    branches:
      - main
```

### Deploy only on photos:
```yaml
on:
  push:
    branches:
      - main
    paths:
      - 'photos/**'
```

### Deploy on schedule (e.g., daily at midnight):
```yaml
on:
  schedule:
    - cron: '0 0 * * *'  # Daily at midnight UTC
```

## Summary

Your trading photo repository now has a professional CI/CD pipeline! Just add photos, commit, and push - GitHub Actions handles the rest automatically. 🚀

For more details, see:
- `.github/workflows/deploy.yml` - The workflow configuration
- `.github/workflows/README.md` - Workflow documentation
- GitHub Actions docs: https://docs.github.com/en/actions

