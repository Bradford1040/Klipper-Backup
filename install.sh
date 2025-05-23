#!/usr/bin/env bash

SCRIPT_VERSION="3.0.0"

if [[ "$1" == "--version" ]]; then
    echo "Klipper-Backup Installer version $SCRIPT_VERSION"
    exit 0
fi

# After a successful install, record the version:
echo "$SCRIPT_VERSION" > "$parent_path/.installed_version"

if [ -z "$BASH_VERSION" ]; then
    echo "Error: This script must be run with bash." >&2
    exit 1
fi

# Trap Ctrl+C (SIGINT) to ensure terminal echo is restored
trap 'stty echo; echo -e "\n${R}● Installation aborted by user.${NC}"; exit 1' SIGINT

# --- Determine Script's Own Path ---
# Get the absolute path of the directory containing this script
# Handles symlinks correctly.
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
SOURCE="$(readlink "$SOURCE")"
[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
parent_path="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

# --- Source Utilities ---
# Check if utils file exists before sourcing
if [[ -f "$parent_path/utils/utils.sh" ]]; then
    source "$parent_path/utils/utils.sh"
else
    echo "Error: Utility functions not found at '$parent_path/utils/utils.sh'. Cannot continue." >&2
    echo "Try running: git submodule update --init --recursive" >&2
    exit 1
fi

# --- tput fallback helpers ---
tput_civis() { command -v tput &>/dev/null && tput civis; }
tput_cnorm() { command -v tput &>/dev/null && tput cnorm; }

# Must edit before you run ./install.sh
# --- Global Variables ---
# define KLIPPER_DATA_DIR
KLIPPER_DATA_DIR="" # Custom folder name whe using KIAUH to install multiple printers
# Make klipper_base_name global so service functions can access it
declare klipper_base_name
declare FIX_MODE=false # Flag for --fix mode

# --- Ensure stty echo is enabled on exit (fallback) ---
# This trap runs on normal exit (0) or error exit (non-zero)
trap 'stty echo' EXIT

# --- Helper Function Definitions (Full Implementations First) ---

# --- Dependency Check ---
dependencies() {
    loading_wheel "${Y}●${NC} Checking for installed dependencies" &
    local loading_pid=$!
    # Ensure check_dependencies is available from utils.sh
    if command -v check_dependencies &> /dev/null; then
        check_dependencies "jq" "curl" "rsync" "git" # Added git
    else
        echo -e "\r\033[K${R}Error: check_dependencies function not found! Cannot check dependencies.${NC}"
        # Attempt manual check as fallback (basic)
        for cmd in jq curl rsync git; do
            if ! command -v $cmd &> /dev/null; then
                echo -e "${R}Error: Required command '$cmd' not found. Please install it.${NC}"
                kill $loading_pid &>/dev/null || true
                exit 1
            fi
        done
        echo "${Y}Warning: check_dependencies function missing, performed basic check.${NC}"
    fi
    kill $loading_pid &>/dev/null || true
    wait $loading_pid &>/dev/null || true
    echo -e "\r\033[K${G}●${NC} Checking for installed dependencies ${G}Done!${NC}\n"
    sleep 0.5 # Short pause
}

# --- Install/Update Klipper-Backup Repository ---
install_repo() {
    if [[ "$FIX_MODE" == "true" ]] || ask_yn "Do you want to proceed with Klipper-Backup installation/update?"; then
        # Navigate to the chosen Klipper data directory
        if ! cd "$HOME/$KLIPPER_DATA_DIR"; then
            echo -e "${R}Error: Could not navigate to '$HOME/$KLIPPER_DATA_DIR'. Aborting.${NC}"
            exit 1
        fi
        echo "Changed directory to: $(pwd)" # Debugging output
        if [ ! -d "klipper-backup" ]; then
            echo -e "${Y}●${NC} Installing Klipper-Backup into '$KLIPPER_BACKUP_INSTALL_DIR'..."
            loading_wheel "   Cloning repository..." &
            local loading_pid=$!
            # Clone directly into the target directory name 'klipper-backup' inside the current dir
            if git clone -b devel-v3.0 --single-branch https://github.com/Bradford1040/klipper-backup.git klipper-backup > /dev/null 2>&1; then
                kill $loading_pid &>/dev/null || true
                tput_cnorm # Restore cursor visibility
                wait $loading_pid &>/dev/null || true
                echo -e "\r\033[K   ${G}✓ Cloning repository Done!${NC}"
                # Set permissions and copy .env example
                chmod +x "$KLIPPER_BACKUP_INSTALL_DIR/script.sh"
                if [[ -f "$KLIPPER_BACKUP_INSTALL_DIR/.env.example" ]]; then
                    cp "$KLIPPER_BACKUP_INSTALL_DIR/.env.example" "$ENV_FILE_PATH"
                    echo -e "   ${G}✓ Copied .env.example to .env${NC}"
                else
                    echo -e "   ${R}✗ Warning: .env.example not found after clone!${NC}"
                fi
                    if [[ -f "$ENV_FILE_PATH" ]]; then
                    echo -e "   ${Y}Setting default backupPaths in .env...${NC}"
                    local new_backup_paths_content="backupPaths=( \\
\"${KLIPPER_DATA_DIR}/config/*\" \\
)"
                    # This replaces the example line with one pointing to the user's config dir
                    sudo sed -i '/^backupPaths=/,/^\s*)/d' "$ENV_FILE_PATH"
                    echo "$new_backup_paths_content" | sudo tee -a "$ENV_FILE_PATH" > /dev/null
                    # Optional: Add another directory for backup besides the config dir
                    # sudo sed -i "/\"${KLIPPER_DATA_DIR}\/config\/\*\"/a \"${KLIPPER_DATA_DIR}/klipper_logs/*\" \\\\" "$ENV_FILE_PATH"
                    echo -e "   ${G}✓ Default backupPaths set (please review/edit)${NC}"
                    # Add/Update KLIPPER_INSTANCE_NAME in .env
                    echo -e "   ${Y}Setting/Updating KLIPPER_INSTANCE_NAME in .env...${NC}"
                    if grep -q "^KLIPPER_INSTANCE_NAME=" "$ENV_FILE_PATH"; then
                        # Variable exists, update it
                        sudo sed -i "s|^KLIPPER_INSTANCE_NAME=.*|KLIPPER_INSTANCE_NAME=\"${klipper_base_name}\"|" "$ENV_FILE_PATH"
                    else
                        # Variable doesn't exist, append it
                        echo "KLIPPER_INSTANCE_NAME=\"${klipper_base_name}\"" | sudo tee -a "$ENV_FILE_PATH" > /dev/null
                    fi
                    echo -e "   ${G}✓ KLIPPER_INSTANCE_NAME ensured as '${klipper_base_name}' in .env${NC}"
                    fi
                sleep .5
                echo -e "${G}●${NC} Installing Klipper-Backup ${G}Done!${NC}\n"
            else
                kill $loading_pid &>/dev/null || true
                tput_cnorm # Restore cursor visibility
                wait $loading_pid &>/dev/null || true
                echo -e "\r\033[K   ${R}✗ Failed to clone Klipper-Backup repository.${NC}"
                # Attempt to clean up potentially incomplete clone
                rm -rf "$KLIPPER_BACKUP_INSTALL_DIR"
                exit 1
            fi
        else
            # klipper-backup directory exists, check for updates
            check_updates
        fi
        # Return to the original script directory (optional, but good practice)
        cd "$parent_path" || echo "${Y}Warning: Could not return to script directory '$parent_path'.${NC}"
    else
        echo -e "${R}● Installation aborted.${NC}\n"
        exit 1
    fi
}

# --- Check for Updates ---
check_updates() {
    # Ensure we are in the correct directory
    if ! cd "$KLIPPER_BACKUP_INSTALL_DIR"; then
        echo -e "${R}Error: Could not navigate to '$KLIPPER_BACKUP_INSTALL_DIR' to check updates. Skipping.${NC}"
        return
    fi
    echo "Checking for updates in: $(pwd)" # Debugging
    # Fetch latest changes from remote without merging
    git fetch origin devel-v3.0 > /dev/null 2>&1
    local local_hash
    local_hash=$(git rev-parse HEAD)
    local remote_hash
    remote_hash=$(git rev-parse origin/devel-v3.0) # Check against the specific branch
    if [ "$local_hash" = "$remote_hash" ]; then
        echo -e "${G}●${NC} Klipper-Backup ${G}is up to date.${NC}\n"
    else
        echo -e "${Y}●${NC} Update for Klipper-Backup ${Y}Available!${NC}\n"
        if [[ "$FIX_MODE" == "true" ]] || ask_yn "Proceed with update?"; then
            echo -e "${Y}●${NC} Updating Klipper-Backup..."
            loading_wheel "   Pulling changes..." &
            local loading_pid=$!
            # Stash local changes (like .env) before pulling, then reapply
            local stash_needed=false
            if ! git diff --quiet || ! git diff --cached --quiet; then
                echo -e "   ${Y}Stashing local changes...${NC}"
                git stash push -u -m "Klipper-Backup-Installer-Update-$(date +%s)" > /dev/null
                stash_needed=true
            fi
            if git pull origin devel-v3.0 --ff-only > /dev/null 2>&1; then # Try fast-forward first
                kill $loading_pid &>/dev/null || true
                tput_cnorm # Restore cursor visibility
                wait $loading_pid &>/dev/null || true
                echo -e "\r\033[K   ${G}✓ Pulling changes Done!${NC}"
                if $stash_needed; then
                    echo -e "   ${Y}Reapplying stashed changes...${NC}"
                    if ! git stash pop > /dev/null 2>&1; then
                        echo -e "   ${R}✗ Warning: Could not automatically reapply stashed changes.${NC}"
                        echo -e "   ${Y}Your '.env' file might need manual merging. Check with 'git status'.${NC}"
                        # Attempt reset if pop failed badly
                        git reset --hard HEAD > /dev/null 2>&1 || true
                        git stash drop > /dev/null 2>&1 || true # Drop the stash if pop failed
                    else
                        echo -e "   ${G}✓ Stashed changes reapplied.${NC}"
                    fi
                fi
                echo -e "${G}●${NC} Updating Klipper-Backup ${G}Done!${NC}\n\n Restarting installation script to ensure consistency..."
                sleep 2
                # Execute the script again, passing the chosen data dir might be needed if state isn't preserved
                        if [[ "$FIX_MODE" == "true" && -n "$KLIPPER_DATA_DIR" ]]; then
                            exec "$parent_path/install.sh" --fix "$KLIPPER_DATA_DIR"
                        else
                            exec "$parent_path/install.sh"
                        fi
            else
                kill $loading_pid &>/dev/null || true
                tput_cnorm # Restore cursor visibility
                wait $loading_pid &>/dev/null || true
                echo -e "\r\033[K   ${R}✗ Error Updating Klipper-Backup (Maybe conflicting changes).${NC}"
                echo -e "   ${Y}Attempting 'git reset --hard' and restarting script...${NC}"
                git reset --hard origin/devel-v3.0 > /dev/null 2>&1 # Reset to remote branch state
                if $stash_needed; then git stash drop > /dev/null 2>&1 || true; fi # Drop stash if reset
                sleep 2
                        if [[ "$FIX_MODE" == "true" && -n "$KLIPPER_DATA_DIR" ]]; then
                            exec "$parent_path/install.sh" --fix "$KLIPPER_DATA_DIR"
                        else
                            exec "$parent_path/install.sh"
                        fi
            fi
        else
            echo -e "${M}●${NC} Klipper-Backup update ${M}skipped!${NC}\n"
        fi
    fi
    # Return to the original script directory
    cd "$parent_path" || echo "${Y}Warning: Could not return to script directory '$parent_path'.${NC}"
}

# --- Configure .env File ---
configure() {
    local ghtoken_username=""
    local message
    # Check if the target .env file exists and if token is default
    if [[ -f "$ENV_FILE_PATH" ]] && grep -q "github_token=ghp_xxxxxxxxxxxxxxxx" "$ENV_FILE_PATH"; then
        message="Do you want to proceed with configuring the Klipper-Backup .env?"
    elif [[ -f "$ENV_FILE_PATH" ]]; then
        message="Do you want to proceed with reconfiguring the Klipper-Backup .env?"
    else
        echo -e "${R}Error: Cannot configure .env file. '$ENV_FILE_PATH' not found.${NC}"
        echo -e "${Y}Try running the installation again.${NC}"
        return 1 # Indicate failure
    fi
    if ask_yn "$message"; then
        # --- Nested functions for getting user input ---
        # These functions now modify the correct ENV_FILE_PATH
        getToken() {
            echo -e "\nSee: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens"
            echo -e "(Ensure token has 'repo' scope for private repos, or 'public_repo' for public ones)"
            local ghtoken
            ghtoken=$(ask_token "Enter your GitHub token")
            clear
            local result
            result=$(check_ghToken "$ghtoken") # Check Github Token
            if [ "$result" != "" ]; then
                # Use | as sed delimiter to avoid issues with / in token (though unlikely)
                sed -i "s|^github_token=.*|github_token=$ghtoken|" "$ENV_FILE_PATH"
                ghtoken_username=$result # Store username derived from token check
                echo -e "${G}✓ Token validated and saved.${NC}"
            else
                echo "${R}Invalid GitHub token or unable to contact GitHub API.${NC}"
                echo "${Y}Please check token and network connection, then try again.${NC}"
                getToken # Ask again
            fi
        }
        getUser() {
            local ghuser
            ghuser=$(ask_textinput "Enter your GitHub username" "$ghtoken_username") # Suggest username from token check
            clear
            menu # Assuming menu redraws or handles cursor
            local exitstatus
            exitstatus=$?
            if [ $exitstatus = 0 ]; then
                sed -i "s|^github_username=.*|github_username=$ghuser|" "$ENV_FILE_PATH"
            else
                getUser # Ask again
            fi
        }
        getRepo() {
            local ghrepo
            ghrepo=$(ask_textinput "Enter your repository name")
            clear
            menu
            local exitstatus
            exitstatus=$?
            if [ $exitstatus = 0 ]; then
                sed -i "s|^github_repository=.*|github_repository=$ghrepo|" "$ENV_FILE_PATH"
            else
                getRepo
            fi
        }
        local ghuser ghrepo ghtoken
        ghuser=$(grep '^github_username=' "$ENV_FILE_PATH" | cut -d'=' -f2)
        ghrepo=$(grep '^github_repository=' "$ENV_FILE_PATH" | cut -d'=' -f2)
        ghtoken=$(grep '^github_token=' "$ENV_FILE_PATH" | cut -d'=' -f2)
        echo "Checking if repository ${ghuser}/${ghrepo} exists..."
        # Use curl to check. -I gets headers, -L follows redirects. Check for 200 OK or 301/302 Redirect (for renamed repos)
        local http_status
        http_status=$(curl -L -s -o /dev/null -w "%{http_code}" -H "Authorization: token $ghtoken" "https://api.github.com/repos/${ghuser}/${ghrepo}")
            if [[ "$http_status" == "200" ]]; then
                echo "${G}✓ Repository found.${NC}"
            elif [[ "$http_status" == "404" ]]; then
                echo "${Y}Warning: Repository ${ghuser}/${ghrepo} not found or token lacks permissions to see it.${NC}"
                echo "${Y}Please ensure the repository exists on GitHub before the first backup.${NC}"
            elif [[ "$http_status" == "401" ]]; then
                echo "${R}Error: Invalid GitHub token used for repository check (Unauthorized).${NC}"
            # Token validation should have caught this, but double-check
            elif [[ "$http_status" == "403" ]]; then
                echo "${R}Error: Token does not have sufficient scope to check repository, or rate limit hit.${NC}"
            else
                echo "${Y}Warning: Could not definitively check repository status (HTTP Status: $http_status).${NC}"
            echo "${Y}Please ensure the repository exists on GitHub before the first backup.${NC}"
            fi
            sleep 1 # Pause for user to read
        getBranch() {
            local repobranch
            repobranch=$(ask_textinput "Enter your desired branch name" "main")
            clear
            menu
            local exitstatus
            exitstatus=$?
            if [ $exitstatus = 0 ]; then
                # Ensure branch name is quoted in .env if it contains special chars (unlikely but safe)
                sed -i "s|^branch_name=.*|branch_name=\"$repobranch\"|" "$ENV_FILE_PATH"
            else
                getBranch
            fi
        }
        getCommitName() {
            local commitname
            commitname=$(ask_textinput "Enter desired commit username" "$(whoami)")
            clear
            menu
            local exitstatus
            exitstatus=$?
            if [ $exitstatus = 0 ]; then
                sed -i "s|^commit_username=.*|commit_username=\"$commitname\"|" "$ENV_FILE_PATH"
            else
                getCommitName
            fi
        }
        getCommitEmail() {
            local unique_id
            unique_id=$(getUniqueid) # Assuming getUniqueid is from utils
            local commitemail
            commitemail=$(ask_textinput "Enter desired commit email" "$(whoami)@$(hostname --short)-$unique_id")
            clear
            menu
            local exitstatus
            exitstatus=$?
            if [ $exitstatus = 0 ]; then
                sed -i "s|^commit_email=.*|commit_email=\"$commitemail\"|" "$ENV_FILE_PATH"
            else
                getCommitEmail
            fi
        }
        # --- Execute the input gathering functions ---
        # Use a loop for retries if needed, but simple sequence for now
        getToken
        getUser
        getRepo
        getBranch
        getCommitName
        getCommitEmail
        # --- Final cleanup after configuration ---
        echo -e "${G}●${NC} Configuration ${G}Done!${NC}\n"
    else
        # User skipped configuration
        echo -e "${M}●${NC} Configuration ${M}skipped!${NC}\n"
    fi
    # Ensure cursor is on a new line after this section
    echo ""
}

# --- Patch Moonraker Update Manager ---
patch_klipper_backup_update_manager() {
    local moonraker_conf_path="$KLIPPER_CONFIG_DIR/moonraker.conf" # Use derived path
    local moonraker_service_name="moonraker" # Default, adjust if needed (e.g., moonraker-punisher)
    # --- Determine Moonraker Service Name (heuristic) ---
            # klipper_base_name is already globally set based on KLIPPER_DATA_DIR in main()
            # Example: "punisher_data" becomes "punisher", "printer_data" becomes "printer"    
    # Check for the specific service name first (e.g., moonraker-punisher.service)
    # Only check if the base name isn't the default 'printer' (which usually uses 'moonraker.service')
    if [[ "$klipper_base_name" != "printer" ]] && systemctl list-units --full -all | grep -q "moonraker-${klipper_base_name}.service"; then
        moonraker_service_name="moonraker-${klipper_base_name}"
        echo "Detected Moonraker service: $moonraker_service_name"
    # Then check for the default service name (e.g., moonraker.service)
    elif systemctl list-units --full -all | grep -q "moonraker.service"; then
        moonraker_service_name="moonraker" # Explicitly set back to default if found
        echo "Detected Moonraker service: $moonraker_service_name"
    # Fallback if neither specific nor default is found
    else
        # Update warning message to show what was checked
        echo "${Y}Warning: Could not automatically detect Moonraker service name.${NC}"
        echo "${Y}         Checked for 'moonraker-${klipper_base_name}.service' (if applicable) and 'moonraker.service'.${NC}"
        echo "${Y}         Assuming default '$moonraker_service_name'. You may need to adjust manually if patching fails.${NC}"
        # Keep moonraker_service_name as the default "moonraker"
    fi
    # --- Check prerequisites ---
    if [[ ! -d "$HOME/moonraker" ]]; then
        echo -e "${Y}● Moonraker source directory not found ($HOME/moonraker). Skipping update manager patch.${NC}\n"
        return
    fi
    # Use the potentially updated moonraker_service_name here
    if ! systemctl is-active "$moonraker_service_name" >/dev/null 2>&1; then
        echo -e "${Y}● Moonraker service '$moonraker_service_name' is not active. Skipping update manager patch.${NC}\n"
        return
    fi
    if [[ ! -f "$moonraker_conf_path" ]]; then
        echo -e "${R}Error: Moonraker config file not found at '$moonraker_conf_path'. Cannot patch.${NC}\n"
        return
    fi
    # --- Check if already patched ---
    if grep -Eq "^\[update_manager klipper-backup\]\s*$" "$moonraker_conf_path"; then
        echo -e "${M}● Adding Klipper-Backup to update manager skipped! (already added)${NC}\n"
        return
    fi
    # --- Ask user ---
    # ... (ask_yn) ...
    if [[ "$FIX_MODE" == "true" ]] || ask_yn "Add Klipper-Backup to Moonraker update manager?"; then

        echo "${Y}●${NC} Adding Klipper-Backup to update manager..."
        loading_wheel "   Patching $moonraker_conf_path..." &
        local loading_pid=$!

        [[ $(tail -c1 "$moonraker_conf_path" | wc -l) -eq 0 ]] && echo "" | sudo tee -a "$moonraker_conf_path" > /dev/null
        local patch_content
        if ! patch_content=$(sed "s|path = ~/klipper-backup|path = $KLIPPER_BACKUP_INSTALL_DIR|" "$parent_path/install-files/moonraker.conf"); then
            kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
            echo -e "\r\033[K${R}✗ Error creating patch content.${NC}\n"
            return 1
        fi

        if echo "$patch_content" | sudo tee -a "$moonraker_conf_path" > /dev/null; then
            echo -e "\r\033[K   ${G}✓ Patched $moonraker_conf_path${NC}"
            # Use the potentially updated moonraker_service_name here
            echo -e "   ${Y}Restarting Moonraker service ($moonraker_service_name)...${NC}"
            if sudo systemctl restart "$moonraker_service_name.service"; then
                kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
                echo -e "\r\033[K${G}●${NC} Adding Klipper-Backup to update manager ${G}Done!${NC}\n"
            else
                kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
                echo -e "\r\033[K${R}✗ Failed to restart Moonraker service '$moonraker_service_name'.${NC}\n"
                echo -e "${Y}Please restart it manually: sudo systemctl restart $moonraker_service_name.service${NC}"
            fi
        else
            # ... (Error handling for patching remains the same) ...
            kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
            echo -e "\r\033[K${R}✗ Failed to add Klipper-Backup to update manager (Error writing to $moonraker_conf_path).${NC}\n"
            echo -e "${Y}Check permissions and try again.${NC}"
        fi
    else
        # ... (Skipped message remains the same) ...
        echo -e "${M}●${NC} Adding Klipper-Backup to update manager ${M}skipped!${NC}\n"
    fi
}

# Function to handle shell_command.cfg setup
install_shell_command_config() {
local source_example="$parent_path/shell_command.cfg.example"
local target_cfg="$KLIPPER_CONFIG_DIR/shell_command.cfg" # e.g., /home/pi/printer_data/config/shell_command.cfg
local target_dir="$KLIPPER_CONFIG_DIR"                  # e.g., /home/pi/printer_data/config
# Ensure the source example file exists
if [ ! -f "$source_example" ]; then
    echo "Warning: Source file '$source_example' not found. Skipping shell_command.cfg setup."
    return
fi
# Ensure the target config directory exists
if [ ! -d "$target_dir" ]; then
    # This shouldn't happen if Klipper is installed correctly and paths were set, but good to check.
    echo "Error: Klipper config directory '$target_dir' not found!"
    echo "Cannot proceed with shell_command.cfg setup."
    return
fi
    echo ">>> Processing Klipper shell_command configuration..."
if [ ! -f "$target_cfg" ]; then
    # Target file does NOT exist - Copy the example file
    echo "  'shell_command.cfg' not found in '$target_dir'."
    echo "  Copying example file to '$target_cfg'..."
    cp "$source_example" "$target_cfg"
    # Add a reminder for the user
    echo "  IMPORTANT: You MUST edit the new '$target_cfg' to replace <user_name> and <custom_name> with your actual values."
    echo "  The correct path for the command should be: bash $KLIPPER_BACKUP_INSTALL_DIR/script.sh"
else
    # Target file DOES exist - Append if the command isn't already present
    echo "  Found existing 'shell_command.cfg' in '$target_dir'."
    # Check if our specific command section already exists
    if ! grep -q "\[gcode_shell_command update_git_script\]" "$target_cfg"; then
    echo "  Appending Klipper-Backup command section from example..."
    # Add a newline for separation, then a comment, then the content
    {
    echo "" >> "$target_cfg" # Add a blank line separator
    echo "# --- Content added by Klipper-Backup installer ---"
    cat "$source_example"
    } >> "$target_cfg"
    echo "  IMPORTANT: Review the appended section in '$target_cfg'. You MUST edit it to replace <user_name> and <custom_name> with your actual values."
    echo "  The correct path for the command should be: bash $KLIPPER_BACKUP_INSTALL_DIR/script.sh"
    else
    echo "  '[gcode_shell_command update_git_script]' section already found in '$target_cfg'."
    echo "  Skipping append. Please ensure the existing command points to the correct script:"
    echo "  command: bash $KLIPPER_BACKUP_INSTALL_DIR/script.sh"
    fi
fi
echo ">>> Finished processing Klipper shell_command configuration."
}

# inotify-tools installation/compilation logic
# Helper function for compiling inotify-tools
install_inotify_from_source() {
    echo -e "\n${Y}● Compiling latest version of inotify-tools from source (This may take a few minutes)${NC}"
    local build_deps="autoconf autotools-dev automake libtool build-essential git"
    echo "${Y}● Checking/installing build dependencies ($build_deps)...${NC}"
    if ! sudo apt-get update -qq || ! sudo apt-get install -y "$build_deps"; then
        echo -e "${R}● Failed to install build dependencies via apt-get. Cannot proceed with compilation.${NC}"
        return 1
    fi
    echo "${G}● Build dependencies checked/installed.${NC}"
    local source_dir="/tmp/inotify-tools-src-$$" # Use /tmp
    current_dir=$(pwd)
    local current_dir
    sudo rm -rf "$source_dir" # Clean previous attempts
    echo "${Y}● Cloning inotify-tools repository...${NC}"
    loading_wheel "   ${Y}Cloning...${NC}" & local loading_pid=$!
    if git clone --depth 1 https://github.com/inotify-tools/inotify-tools.git "$source_dir" > /dev/null 2>&1; then
        kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
        echo -e "\r\033[K   ${G}✓ Cloning Done!${NC}"
    else
        kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
        echo -e "\r\033[K   ${R}✗ Failed to clone inotify-tools repository.${NC}"
        sudo rm -rf "$source_dir"; return 1
    fi
    cd "$source_dir" || { echo -e "${R}✗ Failed to enter source directory '$source_dir'.${NC}"; sudo rm -rf "$source_dir"; return 1; }
    local build_ok=true
    local build_commands=("./autogen.sh" "./configure --prefix=/usr" "make" "sudo make install")
    for cmd in "${build_commands[@]}"; do
        echo "${Y}● Running: ${cmd}${NC}"
        if output=$($cmd 2>&1); then echo "${G}✓ Success${NC}"; else
            echo -e "${R}✗ Command Failed: ${cmd}${NC}\nOutput:\n$output${NC}"; build_ok=false; break
        fi
    done
    cd "$current_dir" || return 1; echo "${Y}● Cleaning up source directory...${NC}"; sudo rm -rf "$source_dir"
    if ! $build_ok; then echo -e "${R}✗ Failed to compile/install inotify-tools from source.${NC}"; return 1; fi
    if command -v inotifywait &> /dev/null; then echo -e "${G}● Successfully compiled and installed inotify-tools.${NC}"; return 0; else
        echo -e "${R}✗ Compilation reported success, but 'inotifywait' command still not found. Installation failed.${NC}"; return 1
    fi
}

# --- Install File Watch Service ---
install_filewatch_service() {
    local base_service_name="klipper-backup-filewatch"
    local service_name # Will be set dynamically
    # Determine Dynamic Service Name
    # Only add suffix if base name is not 'printer' (default case)
    # If klipper_base_name is "printer", use the default. Otherwise, add suffix.
    if [[ "$klipper_base_name" == "printer" ]]; then
        service_name="$base_service_name" # Use default name for "printer" instance
    else
        service_name="${base_service_name}-${klipper_base_name}"
    fi
    echo "Using filewatch service name: $service_name"
    local service_file_path="/etc/systemd/system/${service_name}.service"
    local source_service_file="$parent_path/install-files/${base_service_name}.service" # Template always uses base name
    local tmp_service_file="/tmp/${service_name}.service"
    # Check if service already exists (using dynamic name)
    if systemctl is-enabled "$service_name" >/dev/null 2>&1 || [[ -f "$service_file_path" ]]; then
        echo -e "${M}● Installing $service_name skipped! (already installed or file exists)${NC}\n"
        return
    fi

    # Check dependency
    if ! command -v inotifywait >/dev/null 2>&1; then
        echo "${Y}inotifywait not found. Attempting to install inotify-tools...${NC}"
        if ! sudo apt-get update -qq || ! sudo apt-get install -y inotify-tools; then
            echo "${Y}Failed to install inotify-tools via apt. Attempting to compile from source...${NC}"
            install_inotify_from_source || {
                echo -e "${R}✗ Failed to install inotify-tools. Cannot install $service_name.${NC}\n"
                return 1
            }
        fi
        # Verify again after install attempt
        if ! command -v inotifywait >/dev/null 2>&1; then
            echo -e "${R}✗ Failed to install inotify-tools even from source. Cannot install $service_name.${NC}\n"
            return 1
        fi
        echo "${G}✓ inotify-tools installed successfully.${NC}"
    fi

    if [[ "$FIX_MODE" == "true" ]] || ask_yn "Install Klipper-Backup File Watch Service ($service_name)?"; then
        echo "${Y}●${NC} Installing $service_name..."
        loading_wheel "   Preparing service file..." &
        local loading_pid=$!
        # Copy template to tmp
        if ! cp "$source_service_file" "$tmp_service_file"; then
            kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
            echo -e "\r\033[K${R}✗ Error copying template service file.${NC}\n"
            return 1
        fi
        # Patch service file in /tmp
        # Escape paths for sed
        local escaped_install_dir # Declare locally before use
        escaped_install_dir=$(sed 's|[&/\\]|\\&|g' <<<"$KLIPPER_BACKUP_INSTALL_DIR") # Corrected pattern
        local escaped_config_dir # Declare locally before use
        escaped_config_dir=$(sed 's|[&/\\]|\\&|g' <<<"$KLIPPER_CONFIG_DIR") # Corrected pattern
        sed -i "s|^WorkingDirectory=.*|WorkingDirectory=$escaped_install_dir|" "$tmp_service_file"
        # Pass KLIPPER_CONFIG_DIR via Environment for filewatch.sh to use
        sed -i "s|Environment=KLIPPER_CONFIG_DIR=.*|Environment=KLIPPER_CONFIG_DIR=$escaped_config_dir|" "$tmp_service_file"
        # Ensure ExecStart points to filewatch.sh inside utils
        sed -i "s|^ExecStart=.*|ExecStart=/usr/bin/env bash $escaped_install_dir/utils/filewatch.sh|" "$tmp_service_file"
        sed -i "s|^User=.*|User=${SUDO_USER:-$USER}|" "$tmp_service_file"
        # Copy patched file from /tmp to /etc/systemd/system
        if sudo cp "$tmp_service_file" "$service_file_path"; then
            sudo systemctl daemon-reload
            echo -e "\r\033[K   ${G}✓ Created $service_file_path${NC}"
            echo -e "   ${Y}Enabling and starting $service_name...${NC}"
            if sudo systemctl enable "$service_name" > /dev/null 2>&1 && sudo systemctl start "$service_name"; then
                kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
                echo -e "\r\033[K${G}●${NC} Installing $service_name ${G}Done!${NC}\n"
            else
                kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
                echo -e "\r\033[K${R}✗ Failed to enable or start $service_name.${NC}\n"
                echo -e "${Y}Check service status: systemctl status $service_name${NC}"
                echo -e "${Y}Check service logs: journalctl -u $service_name${NC}"
            fi
        else
            kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
            echo -e "\r\033[K${R}✗ Failed to install $service_name (Error copying to /etc/systemd/system).${NC}\n"
            echo -e "${Y}Check permissions and try again.${NC}"
        fi
        # Clean up tmp file
        rm -f "$tmp_service_file"
    else
        echo -e "${M}●${NC} Installing $service_name ${M}skipped!${NC}\n"
    fi
}

# --- Install Backup Service (On Boot) ---
install_backup_service() {
    local base_service_name="klipper-backup-on-boot"
    local service_name # Will be set dynamically
    # Determine Dynamic Service Name
    # Only add suffix if base name is not 'printer' (default case)
    # If klipper_base_name is "printer", use the default. Otherwise, add suffix.
    if [[ "$klipper_base_name" == "printer" ]]; then
        service_name="$base_service_name" # Use default name for "printer" instance
    else
        service_name="${base_service_name}-${klipper_base_name}"
    fi
    echo "Using on-boot service name: $service_name"
    # --- End of Added Section ---
    # Removed redundant/incorrect sed and local declaration here
    local service_file_path="/etc/systemd/system/${service_name}.service"
    local source_service_file="$parent_path/install-files/${base_service_name}.service" # Template always uses base name
    local tmp_service_file="/tmp/${service_name}.service"

    # Check if service already exists (using dynamic name)
    if systemctl is-enabled "$service_name" >/dev/null 2>&1 || [[ -f "$service_file_path" ]]; then
        echo -e "${M}● Installing $service_name skipped! (already installed or file exists)${NC}\n"
        return
    fi

    if [[ "$FIX_MODE" == "true" ]] || ask_yn "Install Klipper-Backup On-Boot Service ($service_name)?"; then
        echo "${Y}●${NC} Installing $service_name..."
        loading_wheel "   Preparing service file..." &
        local loading_pid=$!

        # Copy template to tmp
        if ! cp "$source_service_file" "$tmp_service_file"; then
            kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
            echo -e "\r\033[K${R}✗ Error copying template service file.${NC}\n"
            return 1
        fi

        # Patch service file in /tmp
        local escaped_install_dir # Declare locally before use
        escaped_install_dir=$(sed 's|[&/\\]|\\&|g' <<<"$KLIPPER_BACKUP_INSTALL_DIR") # Consistent escaping for '&', '/', and '\'
        sed -i "s|^WorkingDirectory=.*|WorkingDirectory=$escaped_install_dir|" "$tmp_service_file"
        sed -i "s|^ExecStart=.*|ExecStart=/usr/bin/env bash $escaped_install_dir/script.sh -c \"On-Boot Backup\"|" "$tmp_service_file"
        sed -i "s|^User=.*|User=${SUDO_USER:-$USER}|" "$tmp_service_file"

        # Copy patched file from /tmp to /etc/systemd/system
        if sudo cp "$tmp_service_file" "$service_file_path"; then
            sudo systemctl daemon-reload
            echo -e "\r\033[K   ${G}✓ Created $service_file_path${NC}"
            echo -e "   ${Y}Enabling $service_name...${NC}"
            if sudo systemctl enable "$service_name" > /dev/null 2>&1; then
                kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
                echo -e "\r\033[K${G}●${NC} Installing $service_name ${G}Done!${NC}\n"
                echo -e "${M}Note: This service only runs once after booting.${NC}"
            else
                kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
                echo -e "\r\033[K${R}✗ Failed to enable $service_name.${NC}\n"
            fi
        else
            kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
            echo -e "\r\033[K${R}✗ Failed to install $service_name (Error copying to /etc/systemd/system).${NC}\n"
            echo -e "${Y}Check permissions and try again.${NC}"
        fi
        # Clean up tmp file
        rm -f "$tmp_service_file"
    else
        echo -e "${M}●${NC} Installing $service_name ${M}skipped!${NC}\n"
    fi
}

# --- Install Cron Job ---
install_cron() {

    # Define the dynamic comment FIRST, including the instance name
    local cron_job_comment="# Klipper-Backup Cron (${klipper_base_name})"

    # Check if a cron job with this SPECIFIC comment already exists
    if crontab -l 2>/dev/null | grep -Fq "$cron_job_comment"; then
        echo -e "${M}● Installing Cron Job for ${klipper_base_name} skipped! (comment found)${NC}\n"
        return 0 # Not an error, just already done
    fi

    # Check if cron daemon is installed/running (only if not already found)
    if ! command -v crontab &> /dev/null || ! pgrep -x cron > /dev/null && ! pgrep -x crond > /dev/null; then
        echo -e "${Y}● Cron service not detected or crontab command not found. Skipping cron task installation.${NC}\n"
        return 1 # Indicate failure to install
    fi

    # --- Calculate next available minute offset ---
    local max_minute
    # Find the highest minute used by existing Klipper-Backup cron jobs based on the comment pattern
    # We grep for the base comment part, extract the first field (minute), sort numerically descending, take the top one.
    max_minute=$(crontab -l 2>/dev/null | grep '# Klipper-Backup Cron (' | awk '{print $1}' | sort -nr | head -n 1)

    # Default to -2 if no jobs found or if max_minute isn't a number, so the first job gets minute 0
    if [[ -z "$max_minute" || ! "$max_minute" =~ ^[0-9]+$ ]]; then
        max_minute=-2
    fi

    # Calculate the next minute, adding 2
    local next_minute=$((max_minute + 2))
    # --- End of minute calculation ---

    # Ask user
    if [[ "$FIX_MODE" == "true" ]] || ask_yn "Install cron task for ${klipper_base_name}? (automatic backup every 4 hours)"; then

        echo "${Y}●${NC} Installing Cron Job for ${klipper_base_name}..."
        loading_wheel "   Adding cron job..." & local loading_pid=$!
        # Define a unique log file path using the instance name
        local log_file="/tmp/klipper_backup_cron_${klipper_base_name}.log"
        # Define the cron job entry using the dynamic comment
        # Ensure KLIPPER_BACKUP_INSTALL_DIR is correctly quoted
        local cron_job="$next_minute */4 * * * cd '$KLIPPER_BACKUP_INSTALL_DIR' && (echo \"--- Running ${klipper_base_name} Backup ---\"; git status --untracked-files=all; bash script.sh -c \\\"Cron backup - \$(date +'\\\\%x - \\\\%X')\\\") >> \"$log_file\" 2>&1 $cron_job_comment"

        # Add the job using crontab
        # The check using the comment was already done above
        if (crontab -l 2>/dev/null; echo "$cron_job") | crontab -; then
            sleep .5
            kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
            # Use \r\033[K to clear the loading wheel line before printing final status
            echo -e "\r\033[K${G}● Installing Cron Job for ${klipper_base_name} ${G}Done!${NC}\n"
        else
            # This case might be hard to reach if the crontab command itself fails
            kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
            echo -e "\r\033[K${R}✗ Failed to add cron job for ${klipper_base_name}.${NC}\n"
            return 1 # Indicate failure
        fi
    else
        echo -e "${M}●${NC} Installing Cron Job for ${klipper_base_name} ${M}skipped!${NC}\n"
    fi
    return 0 # Indicate success or skipped
}

# Function to check GitHub Token validity using the API
check_ghToken() {
local token="$1"
local api_user_info
local http_status
local username

# Basic check if empty
if [ -z "$token" ]; then
    echo "Error: Token cannot be empty." >&2 # Output errors to stderr
    return 1 # Indicate failure
    fi

    # Attempt to use the token with the GitHub API to get user info
    # -sS: Silent mode but show errors
    # -w "%{http_code}": Output HTTP status code
    # -o >(cat): Capture body output to variable (requires bash >= 4)
    # Use temporary file for body if >(cat) is not desired/compatible
    api_user_info=$(curl -sS -H "Authorization: token $token" https://api.github.com/user -o >(cat) -w "\n%{http_code}")

    # Extract HTTP status code (last line of output)
    http_status=$(echo "$api_user_info" | tail -n1)
    # Extract body (all lines except the last)
    local body
    body=$(echo "$api_user_info" | sed '$d') # sed '$d' deletes the last line

    if [ "$http_status" -eq 200 ]; then
    # Attempt to extract username using jq
    username=$(echo "$body" | jq -r '.login // empty')
    if [[ -n "$username" ]]; then
    echo "$username" # Return username on success
    return 0 # Indicate success
    else
    echo "Error: Could not parse username from GitHub API response." >&2
    # Optionally log the body here for debugging, be careful with sensitive info
    return 1 # Indicate failure (parsing error)
    fi
    elif [ "$http_status" -eq 401 ]; then
    echo "Error: Invalid GitHub token (Unauthorized - $http_status)." >&2
    return 1 # Indicate failure
    else
    echo "Error: Could not verify token (HTTP Status: $http_status). Check network or token scope." >&2
    # Optionally log the body here for debugging
    return 1 # Indicate failure
fi
}

# --- Main Installation Function ---
main() {
    clear
    sudo -v || { echo "${R}Error: sudo privileges required.${NC}"; exit 1; }
    # --- Get Klipper Data Directory from User ---
    if [[ -z "$KLIPPER_DATA_DIR" ]]; then # Only prompt if not already set (e.g., by --fix <dir_name>)
        logo # Show logo first for better presentation
        echo "-----------------------------------------------------"
        echo " Klipper Installation Target Configuration"
        echo "-----------------------------------------------------"
        echo "Please enter the name of your main Klipper data directory."
        echo "This directory should exist in your home folder ($HOME)."
        echo "Examples: printer_data, voron_data, punisher_data"
        echo ""
        local KLIPPER_DATA_DIR_INPUT # Use a local variable for reading input
        while true; do
            # Using read -r -p for better compatibility if utils.sh isn't sourced yet or ask_textinput isn't ideal here
            read -r -p "Enter Klipper data directory name: " KLIPPER_DATA_DIR_INPUT < /dev/tty # Read directly from terminal
            if [[ -z "$KLIPPER_DATA_DIR_INPUT" ]]; then
                echo "${R}Error: Directory name cannot be empty.${NC}"
            elif [[ ! -d "$HOME/$KLIPPER_DATA_DIR_INPUT" ]]; then
                echo "${R}Error: Directory '$HOME/$KLIPPER_DATA_DIR_INPUT' not found.${NC}"
                echo "${Y}Please ensure the directory exists before running this script.${NC}"
            elif [[ ! "$KLIPPER_DATA_DIR_INPUT" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                echo "${R}Error: Directory name may only contain letters, numbers, underscores, and dashes.${NC}"
            else
                KLIPPER_DATA_DIR="$KLIPPER_DATA_DIR_INPUT" # Set the global variable
                # --- Set derived paths globally ---
                KLIPPER_BACKUP_INSTALL_DIR="$HOME/$KLIPPER_DATA_DIR/klipper-backup"
                KLIPPER_CONFIG_DIR="$HOME/$KLIPPER_DATA_DIR/config" # Standard location
                ENV_FILE_PATH="$KLIPPER_BACKUP_INSTALL_DIR/.env"
                echo "${G}Using '$HOME/$KLIPPER_DATA_DIR' as the Klipper data directory.${NC}"
                echo "Klipper-Backup will be installed into: $KLIPPER_BACKUP_INSTALL_DIR"
                echo "-----------------------------------------------------"
                sleep 1 # Give user a moment to read
                break # Exit loop, input is valid
            fi
        done # <<< THIS 'done' MARKS THE END OF THE LOOP
    fi # End of KLIPPER_DATA_DIR prompt block if it ran

    # At this point, KLIPPER_DATA_DIR is set (either from prompt above, or from --fix <dir_name> before main was called)
    # KLIPPER_BACKUP_INSTALL_DIR, KLIPPER_CONFIG_DIR, ENV_FILE_PATH are also set if prompt ran,
    # or if --fix <dir_name> ran.

    # --- Derive Klipper Base Name ---
    # This is derived from the finalized KLIPPER_DATA_DIR.
    klipper_base_name="${KLIPPER_DATA_DIR%_data}"
    echo "Using Klipper data directory: $HOME/$KLIPPER_DATA_DIR"
    echo "Derived Klipper instance base name: $klipper_base_name"
    # --- Proceed with Installation Steps ---
    dependencies
    install_repo # This also handles updates
    configure
    install_shell_command_config
    patch_klipper_backup_update_manager # Uses klipper_base_name internally now
    install_filewatch_service # Will now use global klipper_base_name
    install_backup_service # Will now use global klipper_base_name
    install_cron
    # <<< END OF FINAL MESSAGES
    echo -e "\n${G}● Installation Complete!${NC}"
    echo -e "  Klipper-Backup installed in: ${C}$KLIPPER_BACKUP_INSTALL_DIR${NC}"
    echo -e "  Configuration file (.env): ${C}$ENV_FILE_PATH${NC}"
    echo -e "${Y}Please review the .env file, especially 'backupPaths' and 'exclude'.${NC}"
    echo -e "${Y}If you added the shell command, edit '$KLIPPER_CONFIG_DIR/shell_command.cfg' to replace placeholders.${NC}"
    echo -e "${Y}Remember to configure your GitHub repository secrets if needed for private repos.${NC}"
    # <<< END OF FINAL MESSAGES

} # <<< THIS IS THE END OF THE main() FUNCTION

# --- Dummy/Placeholder functions (if not fully defined in utils.sh) ---
# Replace these with actual implementations or ensure they exist in utils.sh
# service_exists() { systemctl list-units --full -all | grep -q "$1.service"; } # Basic service check
# ask_yn() { local prompt="$1"; local response; while true; do read -p "$prompt (y/N)? " -n 1 -r response < /dev/tty; echo; case "$response" in [yY]) return 0;; [nN]|"") return 1;; *) echo "Please answer yes or no.";; esac; done; }
# loading_wheel() { local chars="/-\|"; local delay=0.1; local message="$@"; tput_civis; while true; do for i in {0..3}; do echo -ne "\r${chars:$i:1} $message"; sleep $delay; done; done & } # Basic wheel
# clearUp() { tput ed; } # Clear from cursor to end of screen
# wantsafter() { echo "network-online.target"; } # Default dependency
# getUniqueid() { date +%s%N | md5sum | head -c 7; } # Simple unique ID
# logo() { echo "--- Klipper Backup Installer ---"; } # Simple logo
# ask_textinput() { local prompt="$1"; local default="$2"; local response; read -p "$prompt [$default]: " response < /dev/tty; echo "${response:-$default}"; } # Basic text input


# --- Script Entry Point ---
# Check if running as root, warn if so
if [[ $EUID -eq 0 ]]; then
echo "${R}Warning: Running this script as root is not recommended.${NC}"
echo "${Y}Please run as a regular user with sudo privileges.${NC}"
    exit 1 # Exit root user
    
elif [ "$1" == "--fix" ]; then
    FIX_MODE=true
    echo -e "${Y}● Fix mode enabled. Attempting to repair/reinstall components with minimal interaction.${NC}"
    if [[ -n "$2" ]]; then # If a second argument (directory name) is provided
        TEMP_KLIPPER_DATA_DIR="$2"
        if [[ -z "$TEMP_KLIPPER_DATA_DIR" ]]; then
            echo -e "${R}Error: Directory name cannot be empty when provided as argument to --fix.${NC}"
            exit 1
        elif [[ ! -d "$HOME/$TEMP_KLIPPER_DATA_DIR" ]]; then
            echo -e "${R}Error: Directory '$HOME/$TEMP_KLIPPER_DATA_DIR' not found.${NC}"
            exit 1
        elif [[ "$TEMP_KLIPPER_DATA_DIR" == *"/"* ]]; then
            echo -e "${R}Error: Please enter only the directory name, not a path, for --fix argument.${NC}"
            exit 1
        else
            KLIPPER_DATA_DIR="$TEMP_KLIPPER_DATA_DIR" # Set it globally
            # Set derived paths (copied from main's prompt logic)
            KLIPPER_BACKUP_INSTALL_DIR="$HOME/$KLIPPER_DATA_DIR/klipper-backup"
            KLIPPER_CONFIG_DIR="$HOME/$KLIPPER_DATA_DIR/config"
            ENV_FILE_PATH="$KLIPPER_BACKUP_INSTALL_DIR/.env"
            # klipper_base_name will be derived in main()
            echo "-----------------------------------------------------"
            main # Call main, it will skip its own prompt due to KLIPPER_DATA_DIR being set
        fi
    else
        # No second argument for --fix, main() will prompt for directory as usual
        main
    fi
# Check if called with specific argument (e.g., for update check only)
elif [ "$1" == "check_updates" ]; then
    # Need to know the target dir for check_updates
    # This mode might be less useful now without knowing the target dir beforehand
    echo "${Y}Warning: 'check_updates' argument requires manual directory navigation.${NC}"
    echo "${Y}Please run the script without arguments for interactive installation/update.${NC}"
else
    # Run the main installation process
    main # <--- This call executes the main function

fi
