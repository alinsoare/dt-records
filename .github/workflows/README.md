# GitHub Actions Workflow

## Automatic Deployment

This repository includes a GitHub Actions workflow that automatically deploys your trading photo gallery to GitHub Pages.

## How It Works

The workflow (`deploy.yml`) automatically runs when:

1. **You push changes** to the `main` branch that affect:
   - Any files in the `photos/` directory
   - The `index.html` file
   - The workflow file itself

2. **You manually trigger it** from the Actions tab on GitHub

## What It Does

1. **Checks out your code** from the repository
2. **Configures GitHub Pages** settings
3. **Uploads your site** as an artifact
4. **Deploys to GitHub Pages** automatically

## Benefits

✅ **No manual deployment** - Just push your changes!
✅ **Fast updates** - Your site updates within 30-60 seconds
✅ **Automatic** - Works in the background without any action needed
✅ **Only when needed** - Only triggers when relevant files change

## Usage

Simply use the normal git workflow:

```bash
# Add your photos
./add-photo.sh screenshot.png

# Commit and push
git add photos/
git commit -m "Add trading photos"
git push
```

The workflow will automatically detect the changes and deploy your updated gallery!

## Viewing Workflow Status

1. Go to your repository on GitHub
2. Click the "Actions" tab
3. You'll see all workflow runs and their status
4. Click any run to see detailed logs

## Manual Deployment

To manually trigger a deployment:

1. Go to your repository on GitHub
2. Click "Actions" tab
3. Click "Deploy to GitHub Pages" in the left sidebar
4. Click "Run workflow" button
5. Click "Run workflow" to confirm

## Troubleshooting

### Workflow not running?
- Check that GitHub Pages source is set to "GitHub Actions" in Settings → Pages
- Verify you pushed to the `main` branch
- Check if your changes affected `photos/` or `index.html`

### Deployment failed?
- Go to Actions tab and check the error logs
- Ensure repository settings allow GitHub Actions
- Check that Pages is enabled in repository settings

### Need help?
- View workflow runs in the Actions tab for detailed logs
- Check GitHub Actions documentation: https://docs.github.com/en/actions

