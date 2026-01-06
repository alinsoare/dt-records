# Day Trading Records - Photo Archive

This repository stores trading screenshots and charts organized by date for easy access and review.

## 📁 Folder Structure

Photos are organized by account ID and date in the following format:
```
photos/
  └── ACCOUNT_ID/
      └── YYYY-MM-DD/
          ├── screenshot1.png
          ├── screenshot2.png
          └── ...
```

Example:
```
photos/
  ├── 89654/
  │   ├── 2025-11-07/
  │   │   ├── trade-entry-1.png
  │   │   └── trade-exit-1.png
  │   └── 2025-11-08/
  │       └── market-analysis.png
  └── 12345/
      └── 2025-11-07/
          └── trade-entry.png
```

## 🌐 Web Access

All photos are accessible via GitHub Pages at:
**https://[your-username].github.io/dt-records/**

You can browse photos by date using the web interface.

## 📤 How to Upload Photos

### Method 1: Using the Helper Script
```bash
# Add a photo for today's date (uses default account: 89654)
./add-photo.sh path/to/your/screenshot.png

# Add a photo for a specific date (uses default account: 89654)
./add-photo.sh path/to/your/screenshot.png 2025-11-07

# Add a photo for a specific date and account
./add-photo.sh path/to/your/screenshot.png 2025-11-07 89654

# Add a photo to a different account
./add-photo.sh path/to/your/screenshot.png 2025-11-07 12345
```

### Method 2: Manual Upload
1. Create folders: `photos/ACCOUNT_ID/YYYY-MM-DD/`
2. Copy your photos into that folder
3. Commit and push:
```bash
git add photos/
git commit -m "Add trading photos for account ACCOUNT_ID on YYYY-MM-DD"
git push origin main
```

### Method 3: GitHub Web Interface
1. Go to your repository on GitHub
2. Navigate to the `photos/` folder
3. Click "Add file" → "Upload files"
4. Create a new folder with the date format `YYYY-MM-DD`
5. Upload your photos

## 🚀 Setup Instructions

### First Time Setup

1. **Create GitHub Repository**
   ```bash
   # On GitHub.com, create a new repository named 'dt-records'
   # Then connect this local repo:
   git remote add origin https://github.com/[your-username]/dt-records.git
   git push -u origin main
   ```

2. **Enable GitHub Pages**
   - Go to your repository on GitHub
   - Click "Settings" → "Pages"
   - Under "Source", select "GitHub Actions"
   - Your site will be published at: `https://[your-username].github.io/dt-records/`
   - The site automatically updates when you push changes to photos or index.html!

3. **Make the helper script executable**
   ```bash
   chmod +x add-photo.sh
   ```

## 📋 Quick Commands

```bash
# Add photos for today (default account: 89654)
./add-photo.sh screenshot1.png

# Add photo to specific account
./add-photo.sh screenshot.png 2025-11-07 12345

# View all photos by account
ls -la photos/89654/

# View photos for specific date
ls -la photos/89654/2025-11-07/

# Push changes to GitHub (auto-deploys via GitHub Actions!)
git add photos/
git commit -m "Add trading photos"
git push
```

## 🤖 Automatic Deployment

This repository includes a GitHub Actions workflow that automatically deploys your site whenever you:
- Add or update photos in the `photos/` directory
- Modify the `index.html` file

Just push your changes and the site updates automatically within 30-60 seconds! No manual deployment needed.

## 🔍 Viewing Photos

- **On GitHub**: Navigate to the `photos/ACCOUNT_ID/` folder and browse by date
- **On Web**: Visit your GitHub Pages URL and use the photo gallery
- **Locally**: Open `index.html` in your browser

## 📝 Notes

- Supported image formats: PNG, JPG, JPEG, GIF, WebP
- Recommended naming: Use descriptive names like `entry-AAPL.png`, `exit-SPY.png`
- The repository is public by default - make it private if needed in GitHub settings

