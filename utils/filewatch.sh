#!/usr/bin/env bash

source "$HOME/punisher_data/klipper-backup/.env"
watchlist=""
for path in "${backupPaths[@]}"; do
    for file in $path; do
        if [ ! -h "$file" ]; then
            file_dir=$(dirname "$file")
            if [ "$file_dir" = "." ]; then
                watchlist+=" $HOME/punisher_data/$file"
            else
                watchlist+=" $HOME/punisher_data/$file_dir"
            fi
        fi
    done
done

watchlist=$(echo "$watchlist" | tr ' ' '\n' | sort -u | tr '\n' ' ')

exclude_pattern=".swp|.tmp|printer-[0-9]*_[0-9]*.cfg|.bak|.bkp"

inotifywait -mrP -e close_write -e move -e delete --exclude "$exclude_pattern" $watchlist |
while read -r path event file; do
    if [ -z "$file" ]; then
        file=$(basename "$path")
    fi
    echo "Event Type: $event, Watched Path: $path, File Name: $file"
    file="$file" /usr/bin/env bash -c "/usr/bin/env bash  $HOME/punisher_data/klipper-backup/script.sh -c \"\$file modified - \$(date +'%x - %X')\"" > /dev/null 2>&1
done
