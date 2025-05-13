#!/usr/bin/env bash

# set dotglob so that bash treats hidden files/folders starting with . correctly when copying them (ex. .themes from mainsail)
shopt -s dotglob

# Set parent directory path
parent_path=$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd -P
)

if [[ ! -f "$parent_path/.installed_version" ]]; then
    echo -e "${Y}Info:${NC} No installed version found. Please run ./install.sh to initialize version tracking."
fi

# Initialize variables from .env file
source "$parent_path"/.env
source "$parent_path"/utils/utils.func

REPO_VERSION="3.0.0"
if [[ -f "$parent_path/.installed_version" ]]; then
    INSTALLED_VERSION=$(cat "$parent_path/.installed_version")
    if [[ "$REPO_VERSION" != "$INSTALLED_VERSION" ]]; then
        echo -e "${Y}Warning:${NC} Installed version is $INSTALLED_VERSION, but repo version is $REPO_VERSION."
        echo "Run ./install.sh to update your installed scripts."
    fi
fi

# Determine backup_path based on KLIPPER_INSTANCE_NAME from .env
if [[ -n "$KLIPPER_INSTANCE_NAME" ]]; then
    backup_path="$HOME/config_backup_${KLIPPER_INSTANCE_NAME}"
else
    # Fallback for older .env files or if KLIPPER_INSTANCE_NAME is somehow not set
    echo -e "${Y}Warning: KLIPPER_INSTANCE_NAME not found or empty in .env. Defaulting to legacy backup path: $HOME/config_backup.${NC}" >&2
    echo -e "${Y}It is recommended to re-run the installer for your Klipper instance(s) to update the .env file for proper multi-instance support.${NC}" >&2
    backup_path="$HOME/config_backup"
fi


# --- Define Fix Function ---
fix() {
    echo -e "${Y}● Attempting to fix Klipper-Backup Git repository at $backup_path...${NC}"

    if [ ! -d "$backup_path/.git" ]; then
        echo -e "${R}Error: No Git repository found at '$backup_path/.git'. Cannot perform Git-related fixes.${NC}"
        echo -e "${Y}Consider running the main backup script once to initialize the repository, or check backup_path in .env.${NC}"
        exit 1 # Exit from fix function, script will terminate due to trap or next exit
    fi

    cd "$backup_path" || { echo -e "${R}Error: Could not navigate to '$backup_path'.${NC}"; exit 1; }

    echo -e "${Y}  -> Resetting any uncommitted changes...${NC}"
    if git reset --hard HEAD > /dev/null 2>&1; then
        echo -e "${G}     ✓ Repository reset to HEAD.${NC}"
    else
        echo -e "${R}     ✗ Failed to reset repository. Manual intervention might be needed.${NC}"
    fi

    echo -e "${Y}  -> Cleaning untracked files (excluding ignored files)...${NC}"
    if git clean -fd > /dev/null 2>&1; then # -d for directories, -f for force. Does not remove files in .gitignore.
        echo -e "${G}     ✓ Untracked files removed.${NC}"
    else
        echo -e "${R}     ✗ Failed to clean untracked files.${NC}"
    fi

    echo -e "${Y}  -> Verifying Git remote 'origin'...${NC}"
    local current_remote_url
    current_remote_url=$(git remote get-url origin 2>/dev/null)
    if [[ "$full_git_url" != "$(git remote get-url origin 2>/dev/null)" ]]; then
        echo -e "${Y}     Remote URL mismatch. Current: '${current_remote_url:-Not set}', Expected: '$full_git_url'${NC}"
        echo -e "${Y}     Setting remote 'origin' URL to: $full_git_url${NC}"
        if git remote set-url origin "$full_git_url"; then
            echo -e "${G}     ✓ Remote 'origin' URL updated.${NC}"
        elif git remote add origin "$full_git_url"; then # If set-url failed because remote doesn't exist
            echo -e "${G}     ✓ Remote 'origin' URL added.${NC}"
        else
            echo -e "${R}     ✗ Failed to set/add remote 'origin' URL.${NC}"
        fi
    else
        echo -e "${G}     ✓ Remote 'origin' URL is correct.${NC}"
    fi

    echo -e "${Y}  -> Verifying Git user configuration...${NC}"
    local expected_user_name="${commit_username:-$(whoami)}"
    local expected_user_email="${commit_email:-$(whoami)@$(hostname --short)-$(date +%s%N | md5sum | head -c 7)}" # Consistent with main script logic

    git config user.name "$expected_user_name"
    git config user.email "$expected_user_email"
    echo -e "${G}     ✓ Git user.name set to '$expected_user_name' and user.email set to '$expected_user_email'.${NC}"

    echo -e "${Y}  -> Attempting to fetch from remote 'origin'...${NC}"
    if git fetch origin > /dev/null 2>&1; then
        echo -e "${G}     ✓ Successfully fetched from origin.${NC}"
    else
        echo -e "${R}     ✗ Failed to fetch from origin. Check network, repository URL, and token/SSH key permissions.${NC}"
    fi

    echo -e "${G}● Fix attempt completed.${NC}"
    echo -e "${Y}Please review any messages above. You may want to try a backup now.${NC}"
    exit 0 # Exit script after fix operation
}

# --- Ensure Backup Path Exists ---
# This needs to happen before lock acquisition so the lock directory can be created.
if [ ! -d "$backup_path" ]; then
    mkdir -p "$backup_path"
fi
# --- Define Lock Directory ---
# Ensure backup_path is defined (it comes from .env or defaults)
lock_dir="$backup_path/.script.lock" # Using a hidden dir inside the backup path

# --- Attempt Lock Acquisition ---
if mkdir "$lock_dir" >/dev/null 2>&1; then
    # Lock acquired successfully, set trap to remove lock on exit
    # This trap runs on EXIT (normal exit), TERM (termination), INT (interrupt Ctrl+C)
    trap 'rmdir "$lock_dir" >/dev/null 2>&1' EXIT TERM INT
    echo "[Lock] Acquired lock: $lock_dir" # Optional: Info message
else
    # Lock acquisition failed, another instance is likely running
    echo "[Lock] Failed to acquire lock: $lock_dir. Another instance may be running. Exiting." >&2
    exit 1 # Exit script
fi
# --- Lock Acquired - Proceed with script ---

# --- Rest of your script starts here ---

loading_wheel "${Y}●${NC} Checking for installed dependencies" &
loading_pid=$!
if command -v check_dependencies &>/dev/null; then
    check_dependencies "jq" "curl" "rsync"
else
    # Fallback: basic check
    for cmd in jq curl rsync; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${R}Error: Required dependency '$cmd' is not installed.${NC}"
            kill $loading_pid &>/dev/null || true
            exit 1
        fi
    done
    echo -e "${Y}Warning: check_dependencies function missing, performed basic check.${NC}"
fi
kill $loading_pid &>/dev/null || true
wait $loading_pid &>/dev/null || true
echo -e "\r\033[K${G}●${NC} Checking for installed dependencies ${G}Done!${NC}\n"
sleep 0.5 # Short pause

# Do not touch these variables, the .env file and the documentation exist for this purpose
allow_empty_commits=${allow_empty_commits:-true}
use_filenames_as_commit_msg=${use_filenames_as_commit_msg:-false}
git_protocol=${git_protocol:-"https"}
git_host=${git_host:-"github.com"}
ssh_user=${ssh_user:-"git"}

if [[ $git_protocol == "ssh" ]]; then
    full_git_url=$git_protocol"://"$ssh_user"@"$git_host"/"$github_username"/"$github_repository".git"
else
    full_git_url=$git_protocol"://"$github_token"@"$git_host"/"$github_username"/"$github_repository".git"
fi

# Default exclude patterns if not defined or empty in .env
if ! declare -p exclude &>/dev/null || [ ${#exclude[@]} -eq 0 ]; then
    default_exclude_patterns=(
        "*.swp" "*.tmp" "printer-[0-9]*_[0-9]*.cfg"
        "*.bak" "*.bkp" "*.csv" "*.zip"
        ".DS_Store" "Thumbs.db"
    )
    exclude=("${default_exclude_patterns[@]}")
    echo "[Info] Using default exclude patterns for rsync and .gitignore."
fi

# Required for checking the use of the commit_message and debug parameter
commit_message_used=false
debug_output=false
# Collect args before they are consumed by getopts
args="$@"

# Check parameters
while [[ $# -gt 0 ]]; do
case "$1" in
    -h|--help)
    show_help
    exit 0
    ;;
    -f|--fix)
    fix
    shift
    ;;
    -c|--commit_message)
    if  [[ -z "$2" || "$2" =~ ^- ]]; then
        echo -e "\r\033[K${R}Error: commit message expected after $1${NC}" >&2
        exit 1
    else
        commit_message="$2"
        commit_message_used=true
        shift 2
    fi
    ;;
    -d|--debug)
    debug_output=true
    shift
    ;;
    *)
    echo -e "\r\033[K${R}Unknown option: $1${NC}"
    show_help
    exit 1
    ;;
esac
done

# Check for updates
[ $(git -C "$parent_path" rev-parse HEAD) = $(git -C "$parent_path" ls-remote $(git -C "$parent_path" rev-parse --abbrev-ref '@{u}' | sed 's/\// /g') | cut -f1) ] && echo -e "Klipper-Backup is up to date\n" || echo -e "${Y}●${NC} Update for Klipper-Backup ${Y}Available!${NC}\n"

# Check if .env is v1 version
if [[ ! -v backupPaths ]]; then
    echo ".env file is not using version 2 config, upgrading to V2"
    if bash $parent_path/utils/v1convert.sh; then
        echo "Upgrade complete restarting script.sh"
        sleep 2.5
        exec "$parent_path/script.sh" "$args"
    fi
fi

if [ "$debug_output" = true ]; then
    # Debug output: Show last command
    begin_debug_line
    if [[ "$SHELL" == */bash* ]]; then
        echo -e "Command: $0 $args"
    fi
    end_debug_line

    # Debug output: .env file with hidden token
    begin_debug_line
    while IFS= read -r line; do
    if [[ $line == github_token=* ]]; then
        echo "github_token=****************"
    else
        echo "$line"
    fi
    done < "$parent_path/.env" # Use relative path
    end_debug_line

    # Debug output: Check git repo
    if [[ $git_host == "github.com" ]]; then
        begin_debug_line
        if curl -fsS "https://api.github.com/repos/${github_username}/${github_repository}" >/dev/null; then
            echo "The GitHub repo ${github_username}/${github_repository} exists (public)"
        else
            echo "Error: no GitHub repo ${github_username}/${github_repository} found (maybe private)"
        fi
        end_debug_line
    fi
fi

cd "$backup_path"

# Debug output: $HOME
[ "$debug_output" = true ] && begin_debug_line && echo -e "\$HOME: $HOME" && end_debug_line

# Debug output: $backup_path - (current) path and content
[ "$debug_output" = true ] && begin_debug_line && echo -e "\$backup_path: $PWD" && echo -e "\nContent of \$backup_path:" && echo -ne "$(ls -la $backup_path)\n" && end_debug_line

# Debug output: $backup_path/.git/config content
if [ "$debug_output" = true ]; then
    begin_debug_line
    echo -e "\$backup_path/.git/config:\n"
    while IFS= read -r line; do
        if [[ $line == *"url ="*@* ]]; then
            masked_line=$(echo "$line" | sed -E 's/(url = https:\/\/)[^@]*(@.*)/\1********\2/')
            echo "$masked_line"
        else
            echo "$line"
        fi
    done < "$backup_path/.git/config"
    end_debug_line
fi

# Check if .git exists else init git repo
if [ ! -d ".git" ]; then
    if git --version | grep -qE 'git version (2\.(2[8-9]|[3-9][0-9]))'; then
                git init --initial-branch="$branch_name" >/dev/null 2>&1
    else
                git init >/dev/null 2>&1
                git checkout -b "$branch_name" >/dev/null 2>&1
    fi
        # If .git directory exists, check branch
        else # .git directory exists
    current_branch=$(git symbolic-ref --short -q HEAD)
    if [[ "$current_branch" != "$branch_name" ]]; then
        echo -e "Branch: $branch_name in .env does not match the currently checked out branch of: $current_branch."
        if git show-ref --quiet --verify "refs/heads/$branch_name"; then
                    git checkout "$branch_name" >/dev/null 2>&1
        else
                    git checkout -b "$branch_name" >/dev/null 2>&1
        fi
    fi
fi

# Check if username is defined in .env
if [[ "$commit_username" != "" ]]; then
    git config user.name "$commit_username"
else
    git config user.name "$(whoami)"
    sed -i "s/^commit_username=.*/commit_username=\"$(whoami)\"/" "$parent_path/.env"
fi

# Check if email is defined in .env
if [[ "$commit_email" != "" ]]; then
    git config user.email "$commit_email"
else
    unique_id=$(date +%s%N | md5sum | head -c 7)
    user_email=$(whoami)@$(hostname --short)-$unique_id
    git config user.email "$user_email"
    sed -i "s/^commit_email=.*/commit_email=\"$user_email\"/" "$parent_path/.env"
fi

# Check if remote origin already exists and create if one does not
if [ -z "$(git remote get-url origin 2>/dev/null)" ]; then
    git remote add origin "$full_git_url"
fi

# Check if remote origin changed and update when it is
if [[ "$full_git_url" != $(git remote get-url origin) ]]; then
    git remote set-url origin "$full_git_url"
fi

# Check if branch exists on remote (newly created repos will not yet have a remote) and pull any new changes
if git ls-remote --exit-code --heads origin $branch_name >/dev/null 2>&1; then
    git pull origin "$branch_name"
    # Delete the pulled files so that the directory is empty again before copying the new backup
    # The pull is only needed so that the repository nows its on latest and does not require rebases or merges
    find "$backup_path" -maxdepth 1 -mindepth 1 ! -name '.git' ! -name 'README.md' -exec rm -rf {} \;
fi

cd "$HOME" # Ensure paths are processed relative to HOME for rsync -R
echo -e "${Y}● Copying files to backup directory...${NC}"

# Build rsync exclude options from the exclude array
rsync_exclude_opts=()
for ex_pattern in "${exclude[@]}"; do
    rsync_exclude_opts+=(--exclude="$ex_pattern")
done

shopt -s nullglob # Globs that match nothing expand to nothing
for path_spec in "${backupPaths[@]}"; do # path_spec is like "printer_data/config/*" or "klipper_config/specific_file.cfg"
    # Shell expands $path_spec here. For example, if path_spec is "dir/*",
    # 'item' will iterate over 'dir/file1', 'dir/file2', etc.
    # If path_spec is "dir/singlefile.cfg", 'item' will be "dir/singlefile.cfg".
    for item in $path_spec; do
        # Check if item exists (nullglob handles no matches by making the loop not run for that $item)
        # but an explicit check can be useful if path_spec was not a glob.
        if [ ! -e "$item" ] && [ ! -L "$item" ]; then
            echo -e "${Y}Warning: File or pattern '$item' (from '$path_spec') not found in $HOME. Skipping.${NC}"
            continue
        fi

        if [ -h "$item" ]; then # Check if the item itself is a symlink
            eI acepted your suggested changes but would like to knowcho "Skipping symbolic link: $item"
            continue
        fi
        # $item is now a path relative to $HOME (e.g., printer_data/config/printer.cfg)
        # rsync -aR "$item" "$backup_path/" will create $backup_path/printer_data/config/printer.cfg
        rsync -aR "${rsync_exclude_opts[@]}" "$item" "$backup_path/"
    done # This 'done' closes the inner loop: for item in $path_spec
done # This 'done' closes the outer loop: for path_spec in "${backupPaths[@]}"
shopt -u nullglob # Revert nullglob to default behavior if it's not desired globally
echo -e "${G}✓ File copying complete.${NC}"
cd "$backup_path" # Return to backup directory for git operations

# Debug output: $backup_path content after running rsync
[ "$debug_output" = true ] && begin_debug_line && echo -e "Content of \$backup_path after rsync:" && echo -ne "$(ls -la $backup_path)\n" && end_debug_line

# Create/overwrite .gitignore in the backup directory with patterns from the exclude array.
# This ensures the .gitignore is specific to the backup content.
echo "# Auto-generated .gitignore for Klipper Backup repository" > "$backup_path/.gitignore"
echo "# These patterns are also used by rsync to exclude files from being copied." >> "$backup_path/.gitignore"
echo "" >> "$backup_path/.gitignore"
for ex_pattern in "${exclude[@]}"; do
    echo "$ex_pattern" >> "$backup_path/.gitignore"
done
echo "[Info] Generated .gitignore in backup directory: $backup_path/.gitignore"

# Individual commit message, if no parameter is set, use the current timestamp as commit message
if [ "$commit_message_used" != "true" ]; then
    commit_message="New backup from $(date +"%x - %X")"
fi

cd "$backup_path"
# Create and add Readme to backup folder if it doesn't already exist
if ! [ -f "README.md" ]; then
    echo -e "# Klipper-Backup 💾 \nKlipper backup script for manual or automated GitHub backups \n\nThis custom backup is provided by [Klipper-Backup](https://github.com/Bradford1040/klipper-backup)." >"$backup_path/README.md"
fi

# Show in commit message which files have been changed
if $use_filenames_as_commit_msg; then
    commit_message=$(git diff --name-only "$branch_name" | xargs -n 1 basename | tr '\n' ' ')
    [ -z "$commit_message" ] && commit_message="Backup: $(date +"%x - %X")"
fi

# Untrack all files so that any new excluded files are correctly ignored and deleted from remote
git rm -r --cached . >/dev/null 2>&1
git add .
git commit --no-gpg-sign -m "$commit_message"
# Check if HEAD still matches remote (Means there are no updates to push) and create an empty commit just informing that there are no new updates to push
if $allow_empty_commits && [[ $(git rev-parse HEAD) == $(git ls-remote $(git rev-parse --abbrev-ref '@{u}' 2>/dev/null | sed 's/\// /g') | cut -f1) ]]; then
    git commit --no-gpg-sign --allow-empty -m "$commit_message - No new changes pushed" # --no-gpg-sign is set as I have verified commits set on GitHub
fi
git push -u origin "$branch_name"

# Remove files except .git folder after backup so that any file deletions can be logged on next backup
# NOTE: The trap set earlier will automatically remove the lock directory AFTER this find command finishes
#       or if the script exits at any point before this.
find "$backup_path" -maxdepth 1 -mindepth 1 ! -name '.git' ! -name 'README.md' ! -name '.script.lock' -exec rm -rf {} \;
# The script will exit here, triggering the EXIT trap which removes the lock directory.