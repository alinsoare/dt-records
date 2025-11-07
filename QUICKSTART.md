# Quick Start Guide 🚀

Get your trading photo gallery online in 3 simple steps!

## ⚡ Quick Setup (5 minutes)

### Option 1: Automated Setup (Recommended)
```bash
./setup-github.sh
```
This interactive script will guide you through:
- Creating your GitHub repository
- Connecting your local repo
- Pushing your code
- Instructions for enabling GitHub Pages

### Option 2: Manual Setup

#### 1️⃣ Create GitHub Repository
- Go to https://github.com/new
- Name: `dt-records`
- Visibility: **Public** ✅
- Click "Create repository"

#### 2️⃣ Push to GitHub
```bash
# Replace YOUR_USERNAME with your GitHub username
git remote add origin https://github.com/YOUR_USERNAME/dt-records.git
git push -u origin main
```

#### 3️⃣ Enable GitHub Pages
- Go to: `https://github.com/YOUR_USERNAME/dt-records/settings/pages`
- Source: **Deploy from a branch**
- Branch: **main** / Folder: **/ (root)**
- Click **Save**

🎉 **Done!** Your site will be live at:
```
https://YOUR_USERNAME.github.io/dt-records/
```

## 📸 Adding Photos

### Add today's photos:
```bash
./add-photo.sh screenshot.png
```

### Add photos for a specific date:
```bash
./add-photo.sh trade-setup.png 2025-11-07
```

### Upload to GitHub:
```bash
git add photos/
git commit -m "Add trading photos"
git push
```

Wait 30-60 seconds, then refresh your GitHub Pages URL to see your photos!

## 📱 Features

- ✅ Photos organized automatically by date
- ✅ Beautiful web gallery with search
- ✅ Click to zoom on any photo
- ✅ Mobile-friendly responsive design
- ✅ Accessible from anywhere via web browser

## 📚 More Help

- **Detailed instructions**: See `SETUP_INSTRUCTIONS.md`
- **Full documentation**: See `README.md`
- **Having issues?** Check the Troubleshooting section in `SETUP_INSTRUCTIONS.md`

---

**Ready to go?** Run `./setup-github.sh` to get started!

