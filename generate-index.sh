#!/bin/bash

# Generate photos.json index file for the web gallery

PHOTOS_DIR="photos"
OUTPUT_FILE="photos.json"

echo "Generating photo index..."

# Function to list image files in a directory
list_images() {
    local dir="$1"
    ls -1 "$dir" 2>/dev/null | grep -iE '\.(png|jpg|jpeg|gif|webp)$' || true
}

# Start building JSON
json_content='['
first_account=true

# Loop through account folders
if [ -d "$PHOTOS_DIR" ]; then
    for account_dir in "$PHOTOS_DIR"/*/ ; do
        if [ -d "$account_dir" ]; then
            account=$(basename "$account_dir")
            
            # Add comma between accounts
            if [ "$first_account" = false ]; then
                json_content="${json_content},"
            fi
            first_account=false
            
            json_content="${json_content}
  {
    \"account\": \"$account\",
    \"dates\": ["
            
            first_date=true
            
            # Loop through date folders
            for date_dir in "$account_dir"*/ ; do
                if [ -d "$date_dir" ]; then
                    date=$(basename "$date_dir")
                    
                    # Get list of photos
                    photos=$(list_images "$date_dir")
                    
                    if [ -n "$photos" ]; then
                        # Add comma between dates
                        if [ "$first_date" = false ]; then
                            json_content="${json_content},"
                        fi
                        first_date=false
                        
                        json_content="${json_content}
      {
        \"date\": \"$date\",
        \"photos\": ["
                        
                        first_photo=true
                        while IFS= read -r photo; do
                            if [ -n "$photo" ]; then
                                # Add comma between photos
                                if [ "$first_photo" = false ]; then
                                    json_content="${json_content},"
                                fi
                                first_photo=false
                                
                                json_content="${json_content}
          \"$photo\""
                            fi
                        done <<< "$photos"
                        
                        json_content="${json_content}
        ]
      }"
                    fi
                fi
            done
            
            json_content="${json_content}
    ]
  }"
        fi
    done
fi

json_content="${json_content}
]"

# Write to file
echo "$json_content" > "$OUTPUT_FILE"

echo "✓ Generated $OUTPUT_FILE with photo index"
echo "Photos indexed successfully!"
