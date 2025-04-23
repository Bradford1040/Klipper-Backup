#!/usr/bin/env bash

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
if [[ -f "$parent_path/utils/utils.func" ]]; then
    source "$parent_path/utils/utils.func"
else
    echo "Error: Utility functions not found at '$parent_path/utils/utils.func'. Cannot continue." >&2
    exit 1
fi

# Must edit before you run ./install.sh
# --- Global Variables ---
# define KLIPPER_DATA_DIR
KLIPPER_DATA_DIR="" # Custom folder name whe using KIAUH to install multiple printers
KLIPPER_BACKUP_INSTALL_DIR="" # Full path to where klipper-backup will be installed
KLIPPER_CONFIG_DIR="" # Full path to the printer config directory (e.g., .../printer_data/config)
ENV_FILE_PATH="" # Full path to the .env file

# --- Ensure stty echo is enabled on exit (fallback) ---
# This trap runs on normal exit (0) or error exit (non-zero)
trap 'stty echo' EXIT

# --- Main Installation Function ---
main() {
    clear
    sudo -v # Prompt for sudo password early if needed

    # --- Get Klipper Data Directory from User ---
    logo # Show logo first for better presentation
    echo "-----------------------------------------------------"
    echo " Klipper Installation Target Configuration"
    echo "-----------------------------------------------------"
    echo "Please enter the name of your main Klipper data directory."
    echo "This directory should exist in your home folder ($HOME)."
    echo "Examples: printer_data, voron_data, punisher_data"
    echo ""
    while true; do
        # Using read -p for better compatibility if utils.func isn't sourced yet or ask_textinput isn't ideal here
        read -p "Enter Klipper data directory name: " KLIPPER_DATA_DIR < /dev/tty # Read directly from terminal

        if [[ -z "$KLIPPER_DATA_DIR" ]]; then
            echo "${R}Error: Directory name cannot be empty.${NC}"
        elif [[ ! -d "$HOME/$KLIPPER_DATA_DIR" ]]; then
            echo "${R}Error: Directory '$HOME/$KLIPPER_DATA_DIR' not found.${NC}"
            echo "${Y}Please ensure the directory exists before running this script.${NC}"
        elif [[ "$KLIPPER_DATA_DIR" == *"/"* ]]; then
             echo "${R}Error: Please enter only the directory name, not a path.${NC}"
        else
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
    done

    # --- Proceed with Installation Steps ---
    dependencies # Check dependencies first
    install_repo # Install/Update Klipper-Backup into the chosen dir
    configure # Configure the .env file in the chosen dir
    patch_klipper_backup_update_manager # Patch moonraker.conf in the chosen dir
    install_filewatch_service # Install service pointing to the chosen dir
    install_backup_service # Install service pointing to the chosen dir
    install_cron # Install cron job pointing to the chosen dir

    echo -e "\n${G}● Installation Complete!${NC}"
    echo -e "  Klipper-Backup installed in: ${C}$KLIPPER_BACKUP_INSTALL_DIR${NC}"
    echo -e "  ${Y}IMPORTANT:${NC} Please verify the ${C}backupPaths${NC} setting in ${C}$ENV_FILE_PATH${NC}"
    echo -e "  It should list paths relative to ${C}$HOME${NC} that you want to back up."
    echo -e "  Example: backupPaths=( \"$KLIPPER_DATA_DIR/config/*\" \"$KLIPPER_DATA_DIR/klipper_logs/*\" )"
    echo -e "\n  For help or further information, read the docs: https://klipperbackup.xyz"
}

# --- Dependency Check ---
dependencies() {
    loading_wheel "${Y}●${NC} Checking for installed dependencies" &
    local loading_pid=$!
    # Ensure check_dependencies is available from utils.func
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
    local questionline=$(getcursor)
    if ask_yn "Do you want to proceed with Klipper-Backup installation/update?"; then
        tput cup $(($questionline - 1)) 0 # Go up one line from cursor
        clearUp # Clear from cursor down

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
            if git clone -b KIAUH_V2 --single-branch https://github.com/Bradford1040/klipper-backup.git klipper-backup > /dev/null 2>&1; then
                kill $loading_pid &>/dev/null || true
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
                    # Use | as delimiter for sed
                    # This replaces the example line with one pointing to the user's config dir
                    sudo sed -i "s|^backupPaths=(.*|backupPaths=( \\\n\"${KLIPPER_DATA_DIR}/config/*\" \\\n)|" "$ENV_FILE_PATH"
                    # Optional: Add another directory for backup besides the config dir
                    # sudo sed -i "/\"${KLIPPER_DATA_DIR}\/config\/\*\"/a \"${KLIPPER_DATA_DIR}/klipper_logs/*\" \\\\" "$ENV_FILE_PATH"
                    echo -e "   ${G}✓ Default backupPaths set (please review/edit)${NC}"
                    fi
                sleep .5
                echo -e "${G}●${NC} Installing Klipper-Backup ${G}Done!${NC}\n"
            else
                kill $loading_pid &>/dev/null || true
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
        tput cup $(($questionline - 1)) 0 # Go up one line
        clearUp # Clear from cursor down
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
    git fetch origin KIAUH_V2 > /dev/null 2>&1

    local local_hash=$(git rev-parse HEAD)
    local remote_hash=$(git rev-parse origin/KIAUH_V2) # Check against the specific branch

    if [ "$local_hash" = "$remote_hash" ]; then
        echo -e "${G}●${NC} Klipper-Backup ${G}is up to date.${NC}\n"
    else
        echo -e "${Y}●${NC} Update for Klipper-Backup ${Y}Available!${NC}\n"
        local questionline=$(getcursor)
        if ask_yn "Proceed with update?"; then
            tput cup $(($questionline - 3)) 0 # Adjust line count based on ask_yn output
            tput ed # Erase from cursor to end of screen

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

            if git pull origin KIAUH_V2 --ff-only > /dev/null 2>&1; then # Try fast-forward first
                kill $loading_pid &>/dev/null || true
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
                # For simplicity, let's just restart. The user will be prompted again.
                exec "$parent_path/install.sh"
            else
                kill $loading_pid &>/dev/null || true
                wait $loading_pid &>/dev/null || true
                echo -e "\r\033[K   ${R}✗ Error Updating Klipper-Backup (Maybe conflicting changes).${NC}"
                echo -e "   ${Y}Attempting 'git reset --hard' and restarting script...${NC}"
                git reset --hard origin/KIAUH_V2 > /dev/null 2>&1 # Reset to remote branch state
                if $stash_needed; then git stash drop > /dev/null 2>&1 || true; fi # Drop stash if reset
                sleep 2
                exec "$parent_path/install.sh"
            fi
        else
            tput cup $(($questionline - 3)) 0 # Adjust line count
            clearUp
            echo -e "${M}●${NC} Klipper-Backup update ${M}skipped!${NC}\n"
        fi
    fi
     # Return to the original script directory
    cd "$parent_path" || echo "${Y}Warning: Could not return to script directory '$parent_path'.${NC}"
}


# --- Configure .env File ---
configure() {
    local ghtoken_username=""
    local questionline=$(getcursor)
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
        tput cup $(($questionline - 1)) 0 # Go up one line
        clearUp # Clear from cursor down

        # --- Nested functions for getting user input ---
        # These functions now modify the correct ENV_FILE_PATH
        local pos1=$(getcursor) # Record starting position for input fields
        local pos2=$(getcursor)

        getToken() {
            echo -e "\nSee: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens"
            echo -e "(Ensure token has 'repo' scope for private repos, or 'public_repo' for public ones)"
            local ghtoken=$(ask_token "Enter your GitHub token")
            local result=$(check_ghToken "$ghtoken") # Check Github Token

            if [ "$result" != "" ]; then
                # Use | as sed delimiter to avoid issues with / in token (though unlikely)
                sed -i "s|^github_token=.*|github_token=$ghtoken|" "$ENV_FILE_PATH"
                ghtoken_username=$result # Store username derived from token check
                echo -e "${G}✓ Token validated and saved.${NC}"
                tput cup $pos2 0 # Return cursor to start of input area
                tput ed # Clear previous lines below cursor
            else
                tput cup $(($pos2 - 1)) 0 # Go up to overwrite previous prompt
                tput ed # Clear lines below
                pos2=$(getcursor) # Reset pos2
                echo "${R}Invalid GitHub token or unable to contact GitHub API.${NC}"
                echo "${Y}Please check token and network connection, then try again.${NC}"
                getToken # Ask again
            fi
        }
        getUser() {
            pos2=$(getcursor) # Update cursor position
            local ghuser=$(ask_textinput "Enter your GitHub username" "$ghtoken_username") # Suggest username from token check

            menu # Assuming menu redraws or handles cursor
            local exitstatus=$?
            if [ $exitstatus = 0 ]; then
                sed -i "s|^github_username=.*|github_username=$ghuser|" "$ENV_FILE_PATH"
                tput cup $pos2 0; tput ed # Clear input area
            else
                tput cup $(($pos2 - 1)) 0; tput ed # Clear input area
                getUser # Ask again
            fi
        }
        getRepo() {
            pos2=$(getcursor)
            local ghrepo=$(ask_textinput "Enter your repository name")

            menu
            local exitstatus=$?
            if [ $exitstatus = 0 ]; then
                sed -i "s|^github_repository=.*|github_repository=$ghrepo|" "$ENV_FILE_PATH"
                tput cup $pos2 0; tput ed
            else
                tput cup $(($pos2 - 1)) 0; tput ed
                getRepo
            fi
        }
        getBranch() {
            pos2=$(getcursor)
            local repobranch=$(ask_textinput "Enter your desired branch name" "main")

            menu
            local exitstatus=$?
            if [ $exitstatus = 0 ]; then
                # Ensure branch name is quoted in .env if it contains special chars (unlikely but safe)
                sed -i "s|^branch_name=.*|branch_name=\"$repobranch\"|" "$ENV_FILE_PATH"
                tput cup $pos2 0; tput ed
            else
                tput cup $(($pos2 - 1)) 0; tput ed
                getBranch
            fi
        }
        getCommitName() {
            pos2=$(getcursor)
            local commitname=$(ask_textinput "Enter desired commit username" "$(whoami)")

            menu
            local exitstatus=$?
            if [ $exitstatus = 0 ]; then
                sed -i "s|^commit_username=.*|commit_username=\"$commitname\"|" "$ENV_FILE_PATH"
                tput cup $pos2 0; tput ed
            else
                tput cup $(($pos2 - 1)) 0; tput ed
                getCommitName
            fi
        }
        getCommitEmail() {
            pos2=$(getcursor)
            local unique_id=$(getUniqueid) # Assuming getUniqueid is from utils
            local commitemail=$(ask_textinput "Enter desired commit email" "$(whoami)@$(hostname --short)-$unique_id")

            menu
            local exitstatus=$?
            if [ $exitstatus = 0 ]; then
                sed -i "s|^commit_email=.*|commit_email=\"$commitemail\"|" "$ENV_FILE_PATH"
                tput cup $pos2 0; tput ed
            else
                tput cup $(($pos2 - 1)) 0; tput ed
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
        tput cup $(($pos1 -1)) 0 # Go back to the line above the first input prompt
        tput ed # Clear everything below
        echo -e "${G}●${NC} Configuration ${G}Done!${NC}\n"

    else
        # User skipped configuration
        tput cup $(($questionline - 1)) 0 # Go up one line
        clearUp # Clear from cursor down
        echo -e "${M}●${NC} Configuration ${M}skipped!${NC}\n"
    fi
     # Ensure cursor is on a new line after this section
     echo ""
}


# --- Patch Moonraker Update Manager ---
patch_klipper_backup_update_manager() {
    local questionline=$(getcursor)
    local moonraker_conf_path="$KLIPPER_CONFIG_DIR/moonraker.conf" # Use derived path
    local moonraker_service_name="moonraker" # Default, adjust if needed (e.g., moonraker-punisher)

    # --- Determine Moonraker Service Name (heuristic) ---
    # Check common service names based on data dir, fallback to default
    if systemctl list-units --full -all | grep -q "moonraker-${KLIPPER_DATA_DIR}.service"; then
        moonraker_service_name="moonraker-${KLIPPER_DATA_DIR}"
        echo "Detected Moonraker service: $moonraker_service_name"
    elif systemctl list-units --full -all | grep -q "moonraker.service"; then
         moonraker_service_name="moonraker"
         echo "Detected Moonraker service: $moonraker_service_name"
    else
        echo "${Y}Warning: Could not automatically detect Moonraker service name. Assuming '$moonraker_service_name'.${NC}"
    fi

    # --- Check prerequisites ---
    if [[ ! -d "$HOME/moonraker" ]]; then
         echo -e "${Y}● Moonraker source directory not found ($HOME/moonraker). Skipping update manager patch.${NC}\n"
         return
    fi
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
    if ask_yn "Add Klipper-Backup to Moonraker update manager?"; then
        tput cup $(($questionline - 1)) 0 # Go up one line
        clearUp # Clear from cursor down

        echo "${Y}●${NC} Adding Klipper-Backup to update manager..."
        loading_wheel "   Patching $moonraker_conf_path..." &
        local loading_pid=$!

        # Ensure newline at EOF
        [[ $(tail -c1 "$moonraker_conf_path" | wc -l) -eq 0 ]] && echo "" | sudo tee -a "$moonraker_conf_path" > /dev/null

        # Prepare the patch content, replacing placeholder with actual path
        local patch_content
        if ! patch_content=$(sed "s|path = ~/klipper-backup|path = $KLIPPER_BACKUP_INSTALL_DIR|" "$parent_path/install-files/moonraker.conf"); then
             kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
             echo -e "\r\033[K${R}✗ Error creating patch content.${NC}\n"
             return 1
        fi

        # Append the patch using tee with sudo
        if echo "$patch_content" | sudo tee -a "$moonraker_conf_path" > /dev/null; then
            echo -e "\r\033[K   ${G}✓ Patched $moonraker_conf_path${NC}"
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
            kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
            echo -e "\r\033[K${R}✗ Failed to add Klipper-Backup to update manager (Error writing to $moonraker_conf_path).${NC}\n"
            echo -e "${Y}Check permissions and try again.${NC}"
        fi
    else
        tput cup $(($questionline - 1)) 0 # Go up one line
        clearUp # Clear from cursor down
        echo -e "${M}●${NC} Adding Klipper-Backup to update manager ${M}skipped!${NC}\n"
    fi
}

#!/bin/bash


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
      echo "" >> "$target_cfg" # Add a blank line separator
      echo "# --- Content added by Klipper-Backup installer ---" >> "$target_cfg"
      cat "$source_example" >> "$target_cfg"
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


# --- Main script execution ---

# ... (Initial checks, path determination, dependency checks) ...

# Prompt for Klipper data directory and set paths (KLIPPER_DATA_DIR, KLIPPER_CONFIG_DIR, KLIPPER_BACKUP_INSTALL_DIR etc.)
# ... (This part MUST run before install_shell_command_config) ...

# Install/Update the repository
install_repo

# Configure the .env file
configure

# <<<=== CALL THE NEW FUNCTION HERE ===>>>
install_shell_command_config

# Patch Moonraker update manager
patch_klipper_backup_update_manager

# Install services/cron
install_filewatch_service
install_backup_service
install_cron

# ... (Final success messages) ...

exit 0


# --- Install Filewatch Service ---
# Includes improved inotify-tools installation/compilation logic

# Helper function for compiling inotify-tools (kept from previous context)
install_inotify_from_source() {
    echo -e "\n${Y}● Compiling latest version of inotify-tools from source (This may take a few minutes)${NC}"
    local build_deps="autoconf autotools-dev automake libtool build-essential git"
    echo "${Y}● Checking/installing build dependencies ($build_deps)...${NC}"
    if ! sudo apt-get update -qq || ! sudo apt-get install -y $build_deps; then
         echo -e "${R}● Failed to install build dependencies via apt-get. Cannot proceed with compilation.${NC}"
         return 1
    fi
    echo "${G}● Build dependencies checked/installed.${NC}"

    local source_dir="/tmp/inotify-tools-src-$$" # Use /tmp
    local current_dir=$(pwd)
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

    cd "$current_dir"; echo "${Y}● Cleaning up source directory...${NC}"; sudo rm -rf "$source_dir"

    if ! $build_ok; then echo -e "${R}✗ Failed to compile/install inotify-tools from source.${NC}"; return 1; fi

    if command -v inotifywait &> /dev/null; then echo -e "${G}● Successfully compiled and installed inotify-tools.${NC}"; return 0; else
        echo -e "${R}✗ Compilation reported success, but 'inotifywait' command still not found. Installation failed.${NC}"; return 1
    fi
}

install_filewatch_service() {
    local questionline=$(getcursor)
    local service_name="klipper-backup-filewatch"
    local service_file="/etc/systemd/system/${service_name}.service"
    local message

    if service_exists $service_name; then
        message="Reinstall the filewatch backup service? (triggers backup on config changes)"
    else
        message="Install the filewatch backup service? (triggers backup on config changes)"
    fi

    if ask_yn "$message"; then
        tput cup $(($questionline - 1)) 0; tput ed # Clear prompt area

        # --- Check/Install inotify-tools ---
        local inotify_ok=false
        echo "${Y}● Checking for required 'inotifywait' command...${NC}"
        if command -v inotifywait &> /dev/null; then
             echo -e "${G}✓ 'inotifywait' found.${NC}"; inotify_ok=true; sleep 0.5
        else
            echo -e "${R}✗ 'inotifywait' not found.${NC}"
            echo "${Y}● Attempting to install 'inotify-tools' via package manager...${NC}"
            sudo apt-get update -qq > /dev/null 2>&1 || echo "${Y}Warning: apt-get update failed, proceeding anyway.${NC}"
            if sudo apt-get install -y inotify-tools; then
                if command -v inotifywait &> /dev/null; then
                    echo -e "${G}✓ Successfully installed 'inotify-tools' via package manager.${NC}"; inotify_ok=true
                else
                    echo -e "${R}✗ Package manager reported success, but 'inotifywait' command still not found.${NC}"
                    echo "${Y}● Falling back to compiling from source.${NC}"
                    if install_inotify_from_source; then inotify_ok=true; fi
                fi
            else
                echo -e "${R}✗ Failed to install 'inotify-tools' via package manager.${NC}"
                echo "${Y}● Falling back to compiling from source.${NC}"
                 if install_inotify_from_source; then inotify_ok=true; fi
            fi
        fi
        # --- End of inotify-tools handling ---

        if ! $inotify_ok; then
            echo -e "${R}✗ Failed to install or find required 'inotifywait'. Cannot install filewatch service.${NC}\n"
            return 1 # Indicate failure
        fi

        # --- Install the service ---
        echo "${Y}● Installing Klipper-Backup filewatch service...${NC}"
        loading_wheel "   ${Y}Installing service...${NC}" & local loading_pid=$!

        local install_success=false
        # Use subshell with error checking for installation steps
        if (
            set -e # Exit subshell on error
            echo "Stopping existing service (if any)..." >&2
            sudo systemctl stop "$service_name.service" >/dev/null 2>&1 || true
            echo "Copying service file..." >&2
            sudo cp "$parent_path/install-files/$service_name.service" "$service_file"
            echo "Patching service file..." >&2
            # Use | as delimiter for sed, safer for paths
            sudo sed -i "s|^After=.*|After=$(wantsafter)|" "$service_file" # Assuming wantsafter() is defined
            sudo sed -i "s|^Wants=.*|Wants=$(wantsafter)|" "$service_file"
            sudo sed -i "s|^User=.*|User=${SUDO_USER:-$USER}|" "$service_file"
            # --- CRITICAL: Update ExecStart path ---
            sudo sed -i "s|ExecStart=.*|ExecStart=$KLIPPER_BACKUP_INSTALL_DIR/utils/filewatch.sh|" "$service_file"
            # --- CRITICAL: Update WorkingDirectory path ---
            sudo sed -i "s|WorkingDirectory=.*|WorkingDirectory=$KLIPPER_BACKUP_INSTALL_DIR|" "$service_file"
            # --- CRITICAL: Update Environment variable for config path ---
            # Add or modify Environment line to pass the config dir path
            if grep -q '^Environment=' "$service_file"; then
                 # Append if line exists but doesn't contain our var
                 if ! grep -q 'KLIPPER_CONFIG_DIR=' "$service_file"; then
                     sudo sed -i '/^Environment=/ s/"$/ KLIPPER_CONFIG_DIR='"$KLIPPER_CONFIG_DIR"'"/' "$service_file"
                 else
                     # Replace if var already exists (e.g., from previous install)
                     sudo sed -i '/^Environment=/ s|KLIPPER_CONFIG_DIR=[^ "]*|KLIPPER_CONFIG_DIR='"$KLIPPER_CONFIG_DIR"'|' "$service_file"
                 fi
            else
                 # Add Environment line if it doesn't exist (insert after [Service])
                 sudo sed -i '/\[Service\]/a Environment="KLIPPER_CONFIG_DIR='"$KLIPPER_CONFIG_DIR"'"' "$service_file"
            fi

            echo "Reloading systemd daemon..." >&2
            sudo systemctl daemon-reload
            echo "Enabling service..." >&2
            sudo systemctl enable "$service_name.service"
            echo "Starting service..." >&2
            sudo systemctl start "$service_name.service"
            sleep 1 # Allow service to start/fail
            echo "Checking service status..." >&2
            sudo systemctl is-active --quiet "$service_name.service"
        ); then
             install_success=true
        else
             install_success=false
             echo -e "${R}✗ Service installation/start failed.${NC}" >&2
        fi

        kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true

        if $install_success; then
            echo -e "\r\033[K${G}✓ Installing filewatch service Done!${NC}\n"
        else
            echo -e "\r\033[K${R}✗ Failed to install or start filewatch service.${NC}\n"
            # Optional: show status for debugging
            # echo "Service status:"
            # sudo systemctl status "$service_name.service" --no-pager || true
            return 1 # Indicate failure
        fi
    else
        tput cup $(($questionline - 1)) 0; tput ed # Clear prompt area
        echo -e "\r\033[K${M}● Installing filewatch service skipped!${NC}\n"
    fi
    return 0 # Indicate success or skipped
}


# --- Install On-Boot Backup Service ---
install_backup_service() {
    local questionline=$(getcursor)
    local service_name="klipper-backup-on-boot"
    local service_file="/etc/systemd/system/${service_name}.service"
    local message

    # Check if service exists
    if service_exists $service_name; then
        message="Reinstall the on-boot backup service?"
    else
        message="Install the on-boot backup service?"
    fi

    if ask_yn "$message"; then
        tput cup $(($questionline - 1)) 0; tput ed # Clear prompt area

        echo "${Y}●${NC} Installing on-boot service..."
        loading_wheel "   ${Y}Installing service...${NC}" & local loading_pid=$!

        local install_success=false
        # Use subshell for installation steps
        if (
            set -e # Exit on error
            sudo systemctl stop "$service_name.service" >/dev/null 2>&1 || true
            sudo cp "$parent_path/install-files/$service_name.service" "$service_file"
            # Use | as delimiter for sed
            sudo sed -i "s|^After=.*|After=$(wantsafter)|" "$service_file"
            sudo sed -i "s|^Wants=.*|Wants=$(wantsafter)|" "$service_file"
            sudo sed -i "s|^User=.*|User=${SUDO_USER:-$USER}|" "$service_file"
            # --- CRITICAL: Update ExecStart path ---
            sudo sed -i "s|ExecStart=.*|ExecStart=$KLIPPER_BACKUP_INSTALL_DIR/script.sh -c \"On-Boot Backup\"|" "$service_file"
             # --- CRITICAL: Update WorkingDirectory path ---
            sudo sed -i "s|WorkingDirectory=.*|WorkingDirectory=$KLIPPER_BACKUP_INSTALL_DIR|" "$service_file"

            sudo systemctl daemon-reload
            sudo systemctl enable "$service_name.service"
            # Don't start the on-boot service immediately, it runs on next boot
            # sudo systemctl start "$service_name.service" # Removed this line
            echo "Service enabled, will run on next boot." >&2
        ); then
            install_success=true
        else
            install_success=false
            echo -e "${R}✗ Service installation/enable failed.${NC}" >&2
        fi

        kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true

        if $install_success; then
            echo -e "\r\033[K${G}✓ Installing on-boot service Done!${NC}\n"
        else
            echo -e "\r\033[K${R}✗ Failed to install or enable on-boot service.${NC}\n"
            return 1
        fi
    else
        tput cup $(($questionline - 1)) 0; tput ed # Clear prompt area
        echo -e "\r\033[K${M}●${NC} Installing on-boot service ${M}skipped!${NC}\n"
    fi
    return 0
}

# --- Install Cron Job ---
install_cron() {
    local questionline=$(getcursor)
    local cron_script_path="$KLIPPER_BACKUP_INSTALL_DIR/script.sh" # Use derived path
    local cron_comment="# Klipper-Backup periodic backup" # Identify the cron job

    # Check if cron daemon is installed/running
    if ! command -v crontab &> /dev/null || ! pgrep -x cron > /dev/null; then
         echo -e "${Y}● Cron service not detected or crontab command not found. Skipping cron task installation.${NC}\n"
         return
    fi

    # Check if the cron job already exists for this specific path
    if crontab -l 2>/dev/null | grep -Fq "$cron_script_path"; then
        echo -e "${M}● Installing cron task skipped! (already installed for this path)${NC}\n"
        return
    fi

    # Ask user
    if ask_yn "Install cron task? (automatic backup every 4 hours)"; then
        tput cup $(($questionline - 1)) 0; tput ed # Clear prompt area

        echo "${Y}●${NC} Installing cron task..."
        loading_wheel "   Adding cron job..." & local loading_pid=$!

        # Define the cron job entry
        local cron_job="0 */4 * * * $cron_script_path -c \"Cron backup - \$(date +'\\%x - \\%X')\" $cron_comment"

        # Add the job using crontab
        if (crontab -l 2>/dev/null; echo "$cron_job") | crontab -; then
            sleep .5
            kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
            echo -e "\r\033[K${G}✓ Installing cron task Done!${NC}\n"
        else
            kill $loading_pid &>/dev/null || true; wait $loading_pid &>/dev/null || true
            echo -e "\r\033[K${R}✗ Failed to install cron task.${NC}\n"
            return 1
        fi
    else
        tput cup $(($questionline - 1)) 0; tput ed # Clear prompt area
        echo -e "${M}●${NC} Installing cron task ${M}skipped!${NC}\n"
    fi
    return 0
}


# --- Dummy/Placeholder functions (if not fully defined in utils.func) ---
# Replace these with actual implementations or ensure they exist in utils.func
# getcursor() { tput cup 999 0; echo -ne "\033[6n"; read -sdR CURPOS; CURPOS=${CURPOS#*[}; echo ${CURPOS%;*}; } # More robust getcursor
# service_exists() { systemctl list-units --full -all | grep -q "$1.service"; } # Basic service check
# ask_yn() { local prompt="$1"; local response; while true; do read -p "$prompt (y/N)? " -n 1 -r response < /dev/tty; echo; case "$response" in [yY]) return 0;; [nN]|"") return 1;; *) echo "Please answer yes or no.";; esac; done; }
# loading_wheel() { local chars="/-\|"; local delay=0.1; local message="$@"; tput civis; while true; do for i in {0..3}; do echo -ne "\r${chars:$i:1} $message"; sleep $delay; done; done & } # Basic wheel
# clearUp() { tput ed; } # Clear from cursor to end of screen
# wantsafter() { echo "network-online.target"; } # Default dependency
# getUniqueid() { date +%s%N | md5sum | head -c 7; } # Simple unique ID
# logo() { echo "--- Klipper Backup Installer ---"; } # Simple logo
# ask_textinput() { local prompt="$1"; local default="$2"; local response; read -p "$prompt [$default]: " response < /dev/tty; echo "${response:-$default}"; } # Basic text input


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
  local body=$(echo "$api_user_info" | sed '$d') # sed '$d' deletes the last line

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



# --- Script Entry Point ---
# Check if running as root, warn if so
if [[ $EUID -eq 0 ]]; then
   echo "${R}Warning: Running this script as root is not recommended.${NC}"
   echo "${Y}Please run as a regular user with sudo privileges.${NC}"
   # Optionally exit: exit 1
fi

# Check if called with specific argument (e.g., for update check only)
if [ "$1" == "check_updates" ]; then
    # Need to know the target dir for check_updates
    # This mode might be less useful now without knowing the target dir beforehand
    echo "${Y}Warning: 'check_updates' argument requires manual directory navigation.${NC}"
    echo "${Y}Please run the script without arguments for interactive installation/update.${NC}"
    # Example: Manually navigate and run check_updates if needed
    # read -p "Enter path to klipper-backup installation: " update_path
    # if [[ -d "$update_path" ]]; then
    #    KLIPPER_BACKUP_INSTALL_DIR="$update_path"
    #    check_updates
    # else
    #    echo "${R}Directory not found.${NC}"
    # fi
else
    # Run the main installation process
    main
fi

# Ensure echo is on before final exit
stty echo
exit 0
