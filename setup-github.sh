#!/bin/bash

# Helper script to setup GitHub repository and Pages
# This script guides you through the setup process

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}  GitHub Pages Setup Helper${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Check if git remote already exists
if git remote get-url origin &> /dev/null; then
    echo -e "${GREEN}✓${NC} Git remote already configured"
    REMOTE_URL=$(git remote get-url origin)
    echo -e "${BLUE}Remote URL:${NC} $REMOTE_URL"
    echo ""
else
    echo -e "${YELLOW}Step 1: Create GitHub Repository${NC}"
    echo "1. Go to https://github.com/new"
    echo "2. Repository name: dt-records"
    echo "3. Make it PUBLIC (required for free GitHub Pages)"
    echo "4. Do NOT initialize with README"
    echo "5. Click 'Create repository'"
    echo ""
    read -p "Press Enter after you've created the repository..."
    echo ""
    
    read -p "Enter your GitHub username: " USERNAME
    
    if [ -z "$USERNAME" ]; then
        echo -e "${RED}Error: Username cannot be empty${NC}"
        exit 1
    fi
    
    REPO_URL="https://github.com/$USERNAME/dt-records.git"
    
    echo ""
    echo -e "${YELLOW}Step 2: Connecting to GitHub...${NC}"
    git remote add origin "$REPO_URL"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Remote added successfully"
    else
        echo -e "${RED}Error: Failed to add remote${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${YELLOW}Step 3: Pushing to GitHub...${NC}"
echo "This may prompt you for your GitHub credentials."
echo "Use your Personal Access Token as the password (not your GitHub password)."
echo ""
read -p "Press Enter to continue..."

git push -u origin main

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓${NC} Successfully pushed to GitHub!"
    echo ""
    echo -e "${YELLOW}Step 4: Enable GitHub Pages${NC}"
    echo "1. Go to: https://github.com/$USERNAME/dt-records/settings/pages"
    echo "2. Under 'Build and deployment':"
    echo "   - Source: GitHub Actions"
    echo "3. Click 'Save' (if needed)"
    echo "4. The workflow will automatically deploy your site!"
    echo ""
    echo -e "${BLUE}Note:${NC} GitHub Actions will auto-deploy whenever you update photos or index.html"
    echo ""
    echo -e "${GREEN}Your site will be available at:${NC}"
    echo -e "${BLUE}https://$USERNAME.github.io/dt-records/${NC}"
    echo ""
    echo -e "${GREEN}✓${NC} Setup complete! Start adding photos with:"
    echo -e "${BLUE}  ./add-photo.sh path/to/screenshot.png${NC}"
else
    echo ""
    echo -e "${RED}Error: Failed to push to GitHub${NC}"
    echo ""
    echo "If you need to create a Personal Access Token:"
    echo "1. Go to: https://github.com/settings/tokens"
    echo "2. Generate new token (classic)"
    echo "3. Select 'repo' scope"
    echo "4. Copy the token and use it as your password when pushing"
    exit 1
fi

