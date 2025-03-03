#!/bin/bash

# Configuration
JELLYFIN_URL="http://[ADD_LOCAL_JELLYFIN_SERVER_HERE]:8096"
JELLYFIN_API_KEY=""  # You'll need to fill this in
CACHE_PATH="/mnt/cache"
ARRAY_PATH="/mnt/disk1" #You'll need to check the ARRAY_PATH path for your specific case
MAX_FILES=1  # Set to 0 for no limit
CACHE_THRESHOLD=75  # Percentage threshold for cache usage

# User IDs - add more as needed
declare -a JELLYFIN_USER_IDS=(
    "YOUR_FIRST_USER_ID_HERE"  # First user
    "YOUR_SECOND_USER_ID_HERE"           # Second user - replace with actual ID
)

# Create temporary directory for our files
TEMP_DIR=$(mktemp -d)
RESPONSE_FILE="$TEMP_DIR/jellyfin_response.json"
MERGED_FILE="$TEMP_DIR/merged_items.json"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Function to log messages with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to get played items from Jellyfin for a specific user
get_user_played_items() {
    local user_id="$1"
    local output_file="$2"
    
    log_message "Getting played items for user: $user_id"
    
    # Create URL with Fields=Path parameter
    local api_url="$JELLYFIN_URL/Users/$user_id/Items"
    local query_params="IsPlayed=true&IncludeItemTypes=Movie,Episode&Fields=Path&SortBy=LastPlayedDate&SortOrder=Descending&Recursive=true"
    local full_url="${api_url}?${query_params}"
    
    log_message "API URL: $full_url"
    
    # Make the curl request
    if ! curl -s -S \
        -H "X-MediaBrowser-Token: $JELLYFIN_API_KEY" \
        -H "Accept: application/json" \
        "$full_url" > "$output_file" 2>/dev/null; then
        
        log_message "ERROR: Curl request failed for user $user_id"
        return 1
    fi
    
    # Check if we got a response
    if [ ! -s "$output_file" ]; then
        log_message "ERROR: Empty response from API for user $user_id"
        return 1
    fi
    
    # Validate JSON and get total count
    if ! total_items=$(jq '.Items | length' "$output_file" 2>/dev/null); then
        log_message "ERROR: Invalid JSON response for user $user_id"
        log_message "Response content:"
        head -n 50 "$output_file"
        return 1
    fi
    
    log_message "Total played items found for user $user_id: $total_items"
    return 0
}

# Function to get played items from all users
get_played_items() {
    local temp_response
    local first=true
    local all_items=""
    
    # Process each user
    for user_id in "${JELLYFIN_USER_IDS[@]}"; do
        temp_response="$TEMP_DIR/response_${user_id}.json"
        
        if get_user_played_items "$user_id" "$temp_response"; then
            # Extract items and append to all_items
            if [ "$first" = true ]; then
                all_items=$(jq -c '.Items[]' "$temp_response")
                first=false
            else
                all_items="$all_items"$'\n'$(jq -c '.Items[]' "$temp_response")
            fi
        else
            log_message "WARNING: Failed to get items for user $user_id, continuing with other users"
        fi
    done
    
    # Create final merged JSON with all items
    if [ -n "$all_items" ]; then
        # Convert newline-separated items into a JSON array and wrap in Items object
        echo "$all_items" | jq -s '{"Items": .}' > "$RESPONSE_FILE"
        
        # Get total items
        local total_items
        total_items=$(echo "$all_items" | wc -l)
        log_message "Total played items from all users: $total_items"
        
        # Display all paths for verification
        log_message "Listing all played item paths from all users:"
        log_message "----------------------------------------"
        jq -r '.Items[] | select(.Path != null) | "Title: \(.Name)\nJellyfin Path: \(.Path)\n---"' "$RESPONSE_FILE"
        log_message "----------------------------------------"
        
        return 0
    else
        log_message "ERROR: No valid items found from any user"
        return 1
    fi
}

# Function to convert Jellyfin path to cache path
convert_to_cache_path() {
    local jellyfin_path="$1"
    
    # If path starts with /media/media, remove it
    local relative_path="${jellyfin_path#/media/media/}"
    
    # If there was no /media/media prefix, try removing mount points
    if [ "$relative_path" = "$jellyfin_path" ]; then
        relative_path="${jellyfin_path#/mnt/disk1/}"
        relative_path="${relative_path#/mnt/user/}"
    fi
    
    # Construct cache path
    echo "$CACHE_PATH/media/$relative_path"
}

# Function to convert Jellyfin path to array path
convert_to_array_path() {
    local jellyfin_path="$1"
    
    # If path starts with /media/media, remove it
    local relative_path="${jellyfin_path#/media/media/}"
    
    # If there was no /media/media prefix, try removing mount points
    if [ "$relative_path" = "$jellyfin_path" ]; then
        relative_path="${jellyfin_path#/mnt/disk1/}"
        relative_path="${relative_path#/mnt/user/}"
    fi
    
    # Construct array path
    echo "$ARRAY_PATH/media/$relative_path"
}

# Function to check cache usage percentage
check_cache_usage() {
    local total_space used_space usage_percent
    
    # Get cache drive space info
    if ! df_output=$(df -P "$CACHE_PATH" 2>/dev/null); then
        log_message "ERROR: Failed to get cache drive information"
        return 1
    fi
    
    # Extract usage percentage (use awk to get the percentage from the last line)
    usage_percent=$(echo "$df_output" | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ -z "$usage_percent" ]; then
        log_message "ERROR: Failed to calculate cache usage percentage"
        return 1
    fi
    
    log_message "Current cache usage: $usage_percent%"
    log_message "Cache threshold: $CACHE_THRESHOLD%"
    
    # Return true (0) if usage is above threshold, false (1) if below
    if [ "$usage_percent" -ge "$CACHE_THRESHOLD" ]; then
        log_message "Cache usage is above threshold, will process files"
        return 0
    else
        log_message "Cache usage is below threshold, no action needed"
        return 1
    fi
}

# Function to safely move file using rsync
safe_move_file() {
    local source="$1"
    local dest="$2"
    
    # rsync flags:
    # -a: archive mode (preserves permissions, timestamps, etc.)
    # -v: verbose
    # -h: human-readable sizes
    # -P: show progress and allow resume
    # --remove-source-files: delete source file after successful transfer
    # --checksum: verify file integrity
    
    log_message "  Starting rsync transfer..."
    if rsync -avhP --remove-source-files --checksum "$source" "$dest" 2>&1; then
        # Check if source file is gone (indicating successful move)
        if [ ! -f "$source" ]; then
            log_message "  Transfer completed and verified"
            return 0
        else
            log_message "  ERROR: Source file still exists after transfer"
            return 1
        fi
    else
        log_message "  ERROR: rsync transfer failed"
        return 1
    fi
}

# Function to check and remove empty directories
cleanup_empty_dirs() {
    local dir="$1"
    local base_cache_dir="$CACHE_PATH/media"
    
    # Don't try to remove the base media directory
    if [ "$dir" = "$base_cache_dir" ]; then
        return 0
    fi
    
    # Check if directory is empty
    if [ -d "$dir" ] && [ -z "$(ls -A "$dir")" ]; then
        log_message "  Found empty directory: $dir"
        if rmdir "$dir" 2>/dev/null; then
            log_message "  Removed empty directory"
            # Recursively check parent directory
            cleanup_empty_dirs "$(dirname "$dir")"
        else
            log_message "  WARNING: Failed to remove empty directory"
        fi
    fi
}

# Function to process played items
process_played_items() {
    local moved_count=0
    local skipped_count=0
    local error_count=0
    
    log_message "Processing played items..."
    log_message "Will move up to $MAX_FILES files"
    
    # Read paths from response file
    while IFS= read -r jellyfin_path; do
        # Check if we've moved enough files
        if [ "$MAX_FILES" -gt 0 ] && [ "$moved_count" -ge "$MAX_FILES" ]; then
            log_message "Reached target number of moved files ($MAX_FILES), stopping..."
            break
        fi
        
        if [ -z "$jellyfin_path" ]; then
            continue
        fi
        
        # Convert paths
        local cache_path=$(convert_to_cache_path "$jellyfin_path")
        local array_path=$(convert_to_array_path "$jellyfin_path")
        
        log_message "Processing file:"
        log_message "  Original path: $jellyfin_path"
        log_message "  Cache path: $cache_path"
        log_message "  Array path: $array_path"
        
        if [ -f "$cache_path" ]; then
            log_message "  File found on cache, checking target directory..."
            
            # Check if target directory exists and create if needed
            local target_dir=$(dirname "$array_path")
            if [ ! -d "$target_dir" ]; then
                log_message "  Target directory does not exist, creating: $target_dir"
                if ! mkdir -p "$target_dir"; then
                    log_message "  ERROR: Failed to create target directory"
                    ((error_count++))
                    log_message "  ---"
                    continue
                fi
                log_message "  Successfully created target directory"
            fi
            
            log_message "  Moving file..."
            if safe_move_file "$cache_path" "$array_path"; then
                log_message "  SUCCESS: Moved file to array"
                ((moved_count++))
                log_message "  Successfully moved $moved_count of $MAX_FILES files"
                
                # Check and cleanup empty directories after successful move
                log_message "  Checking for empty directories..."
                cleanup_empty_dirs "$(dirname "$cache_path")"
            else
                log_message "  ERROR: Failed to move file"
                ((error_count++))
            fi
        else
            log_message "  File not found on cache, skipping"
            ((skipped_count++))
        fi
        log_message "  ---"
    done < <(jq -r '.Items[] | select(.Path != null) | .Path' "$RESPONSE_FILE")
    
    # Print summary
    log_message "----------------------------------------"
    log_message "Processing complete!"
    log_message "Files moved to array: $moved_count"
    log_message "Files not on cache: $skipped_count"
    log_message "Errors encountered: $error_count"
    log_message "----------------------------------------"
}

# Function to check for ongoing system operations
check_system_operations() {
    # Check for ongoing parity check/rebuild
    if [ -f "/proc/mdcmd" ]; then
        if grep -q "check\|rebuild" /proc/mdcmd; then
            log_message "ERROR: Parity check or rebuild is in progress. Aborting."
            return 1
        fi
    fi

    # Check for active mover operations
    if [ -f "/var/run/mover.pid" ]; then
        if kill -0 "$(cat /var/run/mover.pid)" 2>/dev/null; then
            log_message "ERROR: Mover is currently running. Aborting."
            return 1
        fi
    fi

    return 0
}

# Main execution
log_message "=== Starting Jellyfin Smart Mover ==="

# Check for ongoing system operations
if ! check_system_operations; then
    log_message "Exiting due to ongoing system operations"
    exit 1
fi

# Check if API key is set
if [ -z "$JELLYFIN_API_KEY" ]; then
    log_message "ERROR: Please set JELLYFIN_API_KEY first"
    exit 1
fi

# Check cache usage first
log_message "Checking cache usage..."
if ! check_cache_usage; then
    log_message "Cache usage is below threshold, no action needed"
    exit 0
fi

# If we get here, cache is above threshold
log_message "Cache usage is above threshold, proceeding with file moves"
log_message "Will process up to $MAX_FILES files"

# Step 1: Get played items
log_message "Step 1: Getting played items from Jellyfin"
if ! get_played_items; then
    log_message "Failed to get played items"
    exit 1
fi

# Step 2: Process items
log_message "Step 2: Processing items for moving"
process_played_items

log_message "=== Process Complete ==="
