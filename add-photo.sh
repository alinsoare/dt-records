#!/bin/bash

# Script to add trading photos organized by account ID and date
# Usage: ./add-photo.sh <photo_file> [date] [account_id]
# If date is not provided, uses today's date
# If account_id is not provided, uses default 89654

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PHOTOS_DIR="$SCRIPT_DIR/photos"

# Default account ID
DEFAULT_ACCOUNT_ID="89654"

# Function to display usage
usage() {
    echo "Usage: $0 <photo_file> [date] [account_id]"
    echo ""
    echo "Arguments:"
    echo "  photo_file    Path to the photo file to add"
    echo "  date          Optional. Date in YYYY-MM-DD format (default: today)"
    echo "  account_id    Optional. Trading account ID (default: $DEFAULT_ACCOUNT_ID)"
    echo ""
    echo "Examples:"
    echo "  $0 screenshot.png"
    echo "  $0 trade-entry.png 2025-11-07"
    echo "  $0 trade-entry.png 2025-11-07 89654"
    echo "  $0 ~/Downloads/*.png  # Add multiple files"
    exit 1
}

# Check if at least one argument is provided
if [ $# -eq 0 ]; then
    usage
fi

# Get date (use provided date or today's date)
if [ $# -ge 2 ]; then
    DATE="$2"
    # Validate date format
    if ! [[ $DATE =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo -e "${RED}Error: Date must be in YYYY-MM-DD format${NC}"
        exit 1
    fi
else
    DATE=$(date +%Y-%m-%d)
fi

# Get account ID (use provided account ID or default)
if [ $# -ge 3 ]; then
    ACCOUNT_ID="$3"
else
    ACCOUNT_ID="$DEFAULT_ACCOUNT_ID"
fi

# Create account/date folder if it doesn't exist
DATE_DIR="$PHOTOS_DIR/$ACCOUNT_ID/$DATE"
mkdir -p "$DATE_DIR"

# Check if photo file exists
PHOTO_FILE="$1"
if [ ! -f "$PHOTO_FILE" ]; then
    echo -e "${RED}Error: File '$PHOTO_FILE' not found${NC}"
    exit 1
fi

# Get the filename
FILENAME=$(date +%s)_$(basename "$PHOTO_FILE")

# Copy the photo to the date folder
cp "$PHOTO_FILE" "$DATE_DIR/$FILENAME"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Photo added successfully!"
    echo -e "${BLUE}Account:${NC} $ACCOUNT_ID"
    echo -e "${BLUE}Location:${NC} $DATE_DIR/$FILENAME"
else
    echo -e "${RED}Error: Failed to copy photo${NC}"
    exit 1
fi

# Regenerate photo index
echo -e "${BLUE}Updating photo index...${NC}"
"$SCRIPT_DIR/generate-index.sh" > /dev/null

git add photos/$ACCOUNT_ID/$DATE/ photos.json
git commit -m "Add trading photos for account $ACCOUNT_ID on $DATE"
git push

