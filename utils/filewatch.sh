#!/usr/bin/env bash

# Determine script's own directory to find the correct .env
parent_path=$(cd "$(dirname "${BASH_SOURCE[0]}")" || exit; cd .. || exit; pwd -P) # Go up one level from utils
if [[ -f "$parent_path/.env" ]]; then
source "$parent_path/.env"
else
echo "Error: Could not find .env file at $parent_path/.env" >&2
exit 1
fi

# Ensure backupPaths is assigned, even if empty, to avoid unbound variable errors
if [[ -z "${backupPaths+x}" ]]; then
    backupPaths=()
fi

# Check if backupPaths is actually an array after sourcing
if ! declare -p backupPaths | grep -q '^declare \-a'; then
    echo "Error: backupPaths is not defined as an array in $parent_path/.env" >&2
    exit 1
fi

# --- Build the watchlist FIRST ---
watchlist=""
echo "Building watchlist from backupPaths in $parent_path/.env:" # Debugging info
for path in "${backupPaths[@]}"; do
    echo "  Processing path: $path" # Debugging info
    # Expand potential wildcards relative to $HOME
    # Use compgen -G for safer glob expansion, handle no matches gracefully
    expanded_paths=$(compgen -G "$HOME/$path" || true)
    if [[ -z "$expanded_paths" ]]; then
        echo "    Warning: Pattern '$HOME/$path' matched no files or directories." # Debugging info
        continue
    fi
    for file_or_dir in $expanded_paths; do
        # Check if expansion yielded existing files/dirs
        if [[ -e "$file_or_dir" ]]; then
            if [ ! -h "$file_or_dir" ]; then # Skip symlinks
                # Get the directory containing the file/item
                # If $file_or_dir is already a directory, dirname works fine
                # If $file_or_dir is a file, it gets the containing directory
                watch_dir=$(dirname "$file_or_dir")
                # Add the directory to the watchlist
                watchlist+=" $watch_dir"
                echo "    Watching directory: $watch_dir" # Debugging info
            else
                echo "    Skipping symlink: $file_or_dir" # Debugging info
            fi
        fi
    done
done

# Make watchlist unique directories and handle potential leading/trailing spaces
watchlist=$(echo "$watchlist" | tr ' ' '\n' | grep -v '^\s*$' | sort -u | tr '\n' ' ')
echo "Final watchlist: $watchlist" # Debugging info
if [[ -z "$watchlist" ]]; then
    echo "Error: Watchlist is empty. No valid directories found to monitor." >&2
    exit 1
fi
# --- End of watchlist building ---

exclude_pattern=".swp|.tmp|printer-[0-9]*_[0-9]*.cfg|.bak|.bkp"

# --- Call inotifywait with the generated watchlist ---
echo "Starting inotifywait..." # Debugging info
inotifywait -mrP -e close_write -e move -e delete --exclude "$exclude_pattern" $watchlist |
while read -r path event file; do
    if [ -z "$file" ]; then
        file=$(basename "$path")
    fi
    echo "Event Type: $event, Watched Path: $path, File Name: $file"
    echo "Waiting 2 minutes before triggering backup..." # Optional: Add a log message
    sleep 120 # Add a 120-second (2 minute) delay
    # Use parent_path determined earlier to find script.sh
    file="$file" /usr/bin/env bash -c "/usr/bin/env bash \"$parent_path/script.sh\" -c \"\$file modified - \$(date +'%x - %X')\"" > /dev/null 2>&1
done

echo "inotifywait finished or was interrupted." # Debugging info
