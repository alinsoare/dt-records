# 📸 How to Use Your Trading Photo Gallery

## 🚀 Quick Start

Your trading photo gallery is now live on GitHub! Here's how to use it:

**Repository:** https://github.com/alinsoare/dt-records

## 📤 Adding Photos

### Daily Workflow:

```bash
# Navigate to your repository
cd /home/alin/daytrading/dt-records

# Add today's trading screenshots
./add-photo.sh ~/path/to/screenshot1.png
./add-photo.sh ~/path/to/screenshot2.png

# Or add multiple at once
./add-photo.sh ~/Screenshots/*.png

# Commit and push to GitHub
git add photos/
git commit -m "Add trading photos for $(date +%Y-%m-%d)"
git push
```

### Add Photos for a Specific Date:

```bash
./add-photo.sh ~/path/to/screenshot.png 2025-11-07
```

## 🌐 Enabling GitHub Pages (One-Time Setup)

To make your photos accessible via web browser:

1. **Sign in to GitHub** at https://github.com
2. **Go to your repository settings:**
   - https://github.com/alinsoare/dt-records/settings/pages
3. **Configure Pages:**
   - **Source:** Deploy from a branch
   - **Branch:** main
   - **Folder:** / (root)
4. **Click "Save"**
5. **Wait 1-2 minutes** for deployment

**Your gallery will be live at:**
```
https://alinsoare.github.io/dt-records/
```

## 📊 Viewing Your Photos

### On the Web:
Visit: https://alinsoare.github.io/dt-records/
- Browse photos organized by date
- Search by date or filename
- Click to zoom on any photo
- Mobile-friendly interface

### On GitHub:
Visit: https://github.com/alinsoare/dt-records/tree/main/photos
- Browse photos by date folders
- Click any photo to view full size

### Locally:
```bash
cd /home/alin/daytrading/dt-records
open index.html  # or: xdg-open index.html
```

## 📁 Folder Structure

```
dt-records/
├── photos/
│   ├── 2025-11-07/
│   │   ├── trade-entry.png
│   │   └── trade-exit.png
│   └── 2025-11-08/
│       └── market-analysis.png
├── index.html              # Web gallery
├── add-photo.sh           # Helper script
└── README.md              # Documentation
```

## 🔄 Common Commands

### Add and push photos:
```bash
cd /home/alin/daytrading/dt-records
./add-photo.sh screenshot.png
git add photos/
git commit -m "Add photos"
git push
```

### Check what's changed:
```bash
git status
```

### View photos by date locally:
```bash
ls -la photos/
```

### Pull latest changes (if editing from multiple computers):
```bash
git pull
```

## 💡 Tips

1. **Name your files descriptively:**
   - Good: `AAPL-entry-morning.png`, `SPY-exit-afternoon.png`
   - Avoid: `screenshot1.png`, `image.png`

2. **Use the helper script:**
   - It automatically organizes photos by date
   - It prevents duplicate filenames

3. **Commit regularly:**
   - Push your photos daily
   - This keeps a backup on GitHub

4. **Repository is PUBLIC:**
   - Anyone with the URL can view your photos
   - To make it private: Settings → Danger Zone → Change visibility
   - Note: Private repos need GitHub Pro for Pages

## 🎯 Example Daily Workflow

```bash
# Morning: Take trading screenshots
# ~/Screenshots/trade-setup-AAPL.png
# ~/Screenshots/entry-SPY.png

# Afternoon: Upload to gallery
cd /home/alin/daytrading/dt-records
./add-photo.sh ~/Screenshots/trade-setup-AAPL.png
./add-photo.sh ~/Screenshots/entry-SPY.png

# Evening: Push to GitHub
git add photos/
git commit -m "Add trading photos for $(date +%Y-%m-%d)"
git push

# View online: https://alinsoare.github.io/dt-records/
```

## 🆘 Troubleshooting

### Photos not showing on website?
- Wait 1-2 minutes after pushing
- Check GitHub Pages is enabled in Settings → Pages
- Hard refresh browser: `Ctrl+Shift+R` (Linux) or `Cmd+Shift+R` (Mac)

### Push failed?
```bash
# Pull latest changes first
git pull

# Then push again
git push
```

### Authentication issues?
```bash
# Check authentication
gh auth status

# Re-authenticate if needed
gh auth login
```

## 📚 Documentation

- **README.md** - Full project documentation
- **QUICKSTART.md** - 5-minute setup guide
- **SETUP_INSTRUCTIONS.md** - Detailed setup steps
- **USAGE.md** (this file) - Daily usage guide

---

**Happy Trading! 📈**

