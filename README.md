# Day Trading Records - Photo Archive

This repository stores trading screenshots and charts organized by date for easy access and review.

## 📁 Folder Structure

Photos are organized by date in the following format:
```
photos/
  └── YYYY-MM-DD/
      ├── screenshot1.png
      ├── screenshot2.png
      └── ...
```

Example:
```
photos/
  ├── 2025-11-07/
  │   ├── trade-entry-1.png
  │   └── trade-exit-1.png
  └── 2025-11-08/
      └── market-analysis.png
```

## 🌐 Web Access

All photos are accessible via GitHub Pages at:
**https://[your-username].github.io/dt-records/**

You can browse photos by date using the web interface.

## 📤 How to Upload Photos

### Method 1: Using the Helper Script
```bash
# Add a photo for today's date
./add-photo.sh path/to/your/screenshot.png

# Add a photo for a specific date
./add-photo.sh path/to/your/screenshot.png 2025-11-07
```

### Method 2: Manual Upload
1. Create a folder with today's date: `photos/YYYY-MM-DD/`
2. Copy your photos into that folder
3. Commit and push:
```bash
git add photos/
git commit -m "Add trading photos for YYYY-MM-DD"
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
   - Under "Source", select "Deploy from a branch"
   - Select branch: `main` and folder: `/ (root)`
   - Click "Save"
   - Your site will be published at: `https://[your-username].github.io/dt-records/`

3. **Make the helper script executable**
   ```bash
   chmod +x add-photo.sh
   ```

## 📋 Quick Commands

```bash
# Add photos for today
./add-photo.sh screenshot1.png screenshot2.png

# View all photos by date
ls -la photos/

# Push changes to GitHub
git add photos/
git commit -m "Add trading photos"
git push
```

## 🔍 Viewing Photos

- **On GitHub**: Navigate to the `photos/` folder and browse by date
- **On Web**: Visit your GitHub Pages URL and use the photo gallery
- **Locally**: Open `index.html` in your browser

## 📝 Notes

- Supported image formats: PNG, JPG, JPEG, GIF, WebP
- Recommended naming: Use descriptive names like `entry-AAPL.png`, `exit-SPY.png`
- The repository is public by default - make it private if needed in GitHub settings

