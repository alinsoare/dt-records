# GitHub Pages Setup Instructions

Follow these steps to publish your trading photos repository to GitHub Pages:

## Step 1: Create GitHub Repository

1. Go to [GitHub.com](https://github.com) and sign in
2. Click the "+" icon in the top right → "New repository"
3. Repository name: `dt-records`
4. Description: "Day Trading Photo Archive"
5. Choose **Public** (required for free GitHub Pages)
6. **DO NOT** initialize with README, .gitignore, or license (we already have these)
7. Click "Create repository"

## Step 2: Push Your Local Repository to GitHub

Copy your GitHub username and run these commands:

```bash
# Replace YOUR_USERNAME with your actual GitHub username
git remote add origin https://github.com/YOUR_USERNAME/dt-records.git

# Add all files to git
git add .

# Commit the files
git commit -m "Initial commit: Setup trading photos repository"

# Push to GitHub
git push -u origin main
```

If prompted for credentials:
- Username: Your GitHub username
- Password: Your Personal Access Token (not your GitHub password)
  - To create a token: GitHub Settings → Developer settings → Personal access tokens → Generate new token

## Step 3: Enable GitHub Pages

1. Go to your repository on GitHub: `https://github.com/YOUR_USERNAME/dt-records`
2. Click "Settings" (top right)
3. Scroll down and click "Pages" in the left sidebar
4. Under "Build and deployment":
   - **Source**: Select "GitHub Actions"
5. The workflow will automatically deploy on the next push

**Note**: The repository includes a GitHub Actions workflow that automatically deploys your site whenever you update photos or index.html. No manual deployment needed!

## Step 4: Access Your Site

Your trading photos will be accessible at:
```
https://YOUR_USERNAME.github.io/dt-records/
```

Example: If your username is `johndoe`, visit:
```
https://johndoe.github.io/dt-records/
```

## Step 5: Test the Setup

1. Visit your GitHub Pages URL
2. You should see the photo gallery interface
3. Add your first photo:
   ```bash
   ./add-photo.sh path/to/your/screenshot.png
   git add photos/
   git commit -m "Add first trading photo"
   git push
   ```
4. Wait 1-2 minutes and refresh your GitHub Pages URL

## Troubleshooting

### Site not showing up?
- Wait a few minutes after enabling GitHub Pages
- Check that your repository is public
- Verify the branch is set to `main` in Pages settings

### Photos not displaying?
- Make sure you've pushed your commits: `git push`
- Clear your browser cache
- Check the browser console for errors (F12)

### Need to make repository private?
- Upgrade to GitHub Pro ($4/month) to use Pages with private repos
- Or keep the repo public (recommended for photo galleries)

## Next Steps

1. Add your trading screenshots using `./add-photo.sh`
2. Commit and push regularly: `git add . && git commit -m "Update" && git push`
3. Share your GitHub Pages URL with anyone you want to access your photos
4. Photos are organized automatically by date!

## Quick Reference

```bash
# Add photo for today
./add-photo.sh screenshot.png

# Add photo for specific date
./add-photo.sh screenshot.png 2025-11-07

# Push changes
git add photos/
git commit -m "Add photos"
git push
```

Your photos will be live at: `https://YOUR_USERNAME.github.io/dt-records/`

