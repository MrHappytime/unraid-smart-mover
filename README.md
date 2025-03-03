# Unraid Smart Mover for Jellyfin

A smart file management script for Unraid servers running Jellyfin that automatically moves watched media content from your cache drive to your array, helping to optimize storage usage and maintain system performance.

## Features

- Automatically detects and moves watched media content from cache to array
- Monitors cache usage to prevent overflow
- Supports multiple Jellyfin users
- Cleans up empty directories after moving files
- Configurable thresholds and limits
- Detailed logging for monitoring operations

## Prerequisites

- Unraid server with cache drive and array configured
- Jellyfin media server installed and running
- `bash` shell
- `curl` for API requests
- `jq` for JSON processing

## Installation

### Primary Method - User Scripts Plugin
1. Install the User Scripts plugin from the Unraid Community Applications (CA)
2. In the Unraid dashboard, go to Settings → User Scripts
3. Click "ADD NEW SCRIPT" and give it a name (e.g., "Jellyfin Smart Mover")
4. Copy the entire contents of `jellyfin_smart_mover.sh` and paste it into the script editor
5. Click "SAVE CHANGES"

You can also set up a schedule for the script to run automatically:
1. Click on the schedule icon (clock) next to your script
2. Select your desired schedule (e.g., daily, hourly, custom cron)
3. Click "SAVE"

### Alternative Methods
- Clone this repository to your Unraid server
- Download and manually copy the script to your preferred location

## Configuration

1. Edit `jellyfin_smart_mover.sh` and configure the following variables:

```bash
JELLYFIN_URL="http://your.jellyfin.server:8096"
JELLYFIN_API_KEY=""  # Your Jellyfin API key
CACHE_PATH="/mnt/cache"
ARRAY_PATH="/mnt/disk1"
MAX_FILES=1  # Set to 0 for no limit
CACHE_THRESHOLD=75  # Percentage threshold for cache usage

# Add your Jellyfin user IDs
declare -a JELLYFIN_USER_IDS=(
    "your-user-id-here"
    "another-user-id-here"
)
```

### Getting Your Jellyfin API Key

1. Log in to your Jellyfin server as an administrator
2. Go to Dashboard → API Keys
3. Create a new API key and copy it
4. Paste the API key into the `JELLYFIN_API_KEY` variable in the script

### Finding User IDs

1. Log in to Jellyfin as an administrator
2. Go to Dashboard → Users
3. Click on a user
4. The user ID is in the URL (the long string of characters)

## Usage

1. If you used the User Scripts plugin, the script will run automatically according to your schedule.
2. If you used an alternative method, make the script executable:
```bash
chmod +x jellyfin_smart_mover.sh
```

3. Run the script:
```bash
./jellyfin_smart_mover.sh
```

For automated execution, you can also set up a cron job.

## How It Works

1. The script queries the Jellyfin API for each configured user to get their watched media items
2. It checks if the cache drive usage is above the configured threshold
3. If the cache needs to be cleared, it moves watched media files from the cache to the array
4. After moving files, it cleans up any empty directories
5. All operations are logged for monitoring

## Safety Features

- Checks for ongoing parity check/rebuild operations before running
- Checks for active mover operations before running
- Checks cache usage before operations
- Verifies file existence before moving
- Uses safe move operations
- Maintains file permissions and ownership
- Cleans up temporary files after execution

## Contributing

Feel free to submit issues and pull requests to improve the script.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
