#!/usr/bin/env bash



trap 'stty echo; exit' SIGINT

parent_path=$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd -P
)

if [[ ! -f .env ]]; then
    cp $parent_path/.env.example $parent_path/.env
fi

# Initialize variables from .env file
source "$parent_path"/.env
source "$parent_path"/utils/utils.func



loading_wheel "${Y}●${NC} Checking for installed dependencies" &


unique_id=$(getUniqueid)

set -e

main() {
    clear
    sudo -v
    dependencies
    logo
    install_repo
    configure
    patch_klipper-backup_update_manager
    install_filewatch_service
    install_backup_service
    install_cron
    echo -e "${G}●${NC} Installation Complete!\n  For help or further information, read the docs: https://klipperbackup.xyz"
}

dependencies() {
    loading_wheel "${Y}●${NC} Checking for installed dependencies" &
    loading_pid=$!
    check_dependencies "jq" "curl" "rsync"
    kill $loading_pid
    echo -e "\r\033[K${G}●${NC} Checking for installed dependencies ${G}Done!${NC}\n"
    sleep 1
}

install_repo() {
    questionline=$(getcursor)
    if ask_yn "Do you want to proceed with installation/(re)configuration?"; then
        tput cup $(($questionline - 1)) 0
        clearUp
        cd "$HOME/punisher_data"
        if [ ! -d "klipper-backup" ]; then
            loading_wheel "${Y}●${NC} Installing Klipper-Backup" &
            loading_pid=$!
            git clone -b KIAUH_V1 --single-branch https://github.com/Bradford1040/klipper-backup.git 2>/dev/null
            chmod +x ./punisher_data/klipper-backup/script.sh
            cp ./punisher_data/klipper-backup/.env.example ./punisher_data/klipper-backup/.env
            sleep .5
            kill $loading_pid
            echo -e "\r\033[K${G}●${NC} Installing Klipper-Backup ${G}Done!${NC}\n"
        else
            check_updates
        fi
    else
        tput cup $(($questionline - 1)) 0
        clearUp
        echo -e "${R}●${NC} Installation aborted.\n"
        exit 1
    fi
}

check_updates() {
    cd ~/punisher_data/klipper-backup
    if [ "$(git rev-parse HEAD)" = "$(git ls-remote $(git rev-parse --abbrev-ref @{u} | sed 's/\// /g') | cut -f1)" ]; then
        echo -e "${G}●${NC} Klipper-Backup ${G}is up to date.${NC}\n"
    else
        echo -e "${Y}●${NC} Update for Klipper-Backup ${Y}Available!${NC}\n"
        questionline=$(getcursor)
        if ask_yn "Proceed with update?"; then
            tput cup $(($questionline - 3)) 0
            tput ed
            loading_wheel "${Y}●${NC} Updating Klipper-Backup" &
            loading_pid=$!
            if git pull >/dev/null 2>&1; then
                kill $loading_pid
                echo -e "\r\033[K${G}●${NC} Updating Klipper-Backup ${G}Done!${NC}\n\n Restarting installation script"
                sleep 1
                exec $parent_path/install.sh
            else
                kill $loading_pid
                echo -e "\r\033[K${R}●${NC} Error Updating Klipper-Backup: Repository is dirty running git reset --hard then restarting script"
                sleep 1
                git reset --hard 2>/dev/null
                exec $parent_path/install.sh
            fi
        else
            tput cup $(($questionline - 3)) 0
            clearUp
            echo -e "${M}●${NC} Klipper-Backup update ${M}skipped!${NC}\n"
        fi
    fi
}

configure() {
    ghtoken_username=""
    questionline=$(getcursor)
    if grep -q "github_token=ghp_xxxxxxxxxxxxxxxx" "$parent_path"/.env; then # Check if the github token still matches the value when initially copied from .env.example
        message="Do you want to proceed with configuring the Klipper-Backup .env?"
    else
        message="Do you want to proceed with reconfiguring the Klipper-Backup .env?"
    fi
    if ask_yn "$message"; then
        tput cup $(($questionline - 1)) 0
        clearUp
        pos1=$(getcursor)
        pos2=$(getcursor)

        getToken() {
            echo -e "See the following for how to create your token: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens (Ensure you set access to the backup repository and have push/pull & commit permissions for the token) \n"    
            ghtoken=$(ask_token "Enter your GitHub token")
            result=$(check_ghToken "$ghtoken") # Check Github Token using github API to ensure token is valid and connection can be established to github
            if [ "$result" != "" ]; then
                sed -i "s/^github_token=.*/github_token=$ghtoken/" "$HOME/punisher_data/klipper-backup/.env"
                ghtoken_username=$result
            else
                tput cup $(($pos2 - 2)) 0
                tput ed
                pos2=$(getcursor)
                echo "Invalid Github token or Unable to contact github API, Please re-enter your token and check for valid connection to github.com then try again!"
                getToken
            fi
        }
        getUser() {
            pos2=$(getcursor)
            ghuser=$(ask_textinput "Enter your github username" "$ghtoken_username")

            menu
            exitstatus=$?
            if [ $exitstatus = 0 ]; then
                sed -i "s/^github_username=.*/github_username=$ghuser/" "$HOME/punisher_data/klipper-backup/.env"
                tput cup $pos2 0
                tput ed
            else
                tput cup $(($pos2 - 1)) 0
                tput ed
                getUser
            fi
        }
        getRepo() {
            pos2=$(getcursor)
            ghrepo=$(ask_textinput "Enter your repository name")

            menu
            exitstatus=$?
            if [ $exitstatus = 0 ]; then
                sed -i "s/^github_repository=.*/github_repository=$ghrepo/" "$HOME/punisher_data/klipper-backup/.env"
                tput cup $pos2 0
                tput ed
            else
                tput cup $(($pos2 - 1)) 0
                tput ed
                getRepo
            fi
        }
        getBranch() {
            pos2=$(getcursor)
            repobranch=$(ask_textinput "Enter your desired branch name" "main")

            menu
            exitstatus=$?
            if [ $exitstatus = 0 ]; then
                sed -i "s/^branch_name=.*/branch_name=\"$repobranch\"/" "$HOME/punisher_data/klipper-backup/.env"
                tput cup $pos2 0
                tput ed
            else
                tput cup $(($pos2 - 1)) 0
                tput ed
                getBranch
            fi
        }
        getCommitName() {
            pos2=$(getcursor)
            commitname=$(ask_textinput "Enter desired commit username" "$(whoami)")

            menu
            exitstatus=$?
            if [ $exitstatus = 0 ]; then
                sed -i "s/^commit_username=.*/commit_username=\"$commitname\"/" "$HOME/punisher_data/klipper-backup/.env"
                tput cup $pos2 0
                tput ed
            else
                tput cup $(($pos2 - 1)) 0
                tput ed
                getCommitName
            fi
        }
        getCommitEmail() {
            pos2=$(getcursor)
            commitemail=$(ask_textinput "Enter desired commit email" "$(whoami)@$(hostname --short)-$unique_id")

            menu
            exitstatus=$?
            if [ $exitstatus = 0 ]; then
                sed -i "s/^commit_email=.*/commit_email=\"$commitemail\"/" "$HOME/punisher_data/klipper-backup/.env"
                tput cup $pos2 0
                tput ed
            else
                tput cup $(($pos2 - 1)) 0
                tput ed
                getCommitEmail
            fi
        }

        while true; do
            set +e
            getToken
            getUser
            getRepo
            getBranch
            getCommitName
            getCommitEmail
            set -e
            break
        done

        tput cup $(($questionline - 1)) 0
        tput ed
        echo -e "\r\033[K${G}●${NC} Configuration ${G}Done!${NC}\n"
        pos1=$(getcursor)
    else
        tput cup $(($questionline - 1)) 0
        clearUp
        echo -e "\r\033[K${M}●${NC} Configuration ${M}skipped!${NC}\n"
        pos1=$(getcursor)
    fi
}

patch_klipper-backup_update_manager() {
    questionline=$(getcursor)
    if [[ -d $HOME/moonraker ]] && systemctl is-active moonraker-punisher >/dev/null 2>&1; then
        if ! grep -Eq "^\[update_manager klipper-backup\]\s*$" "$HOME/punisher_data/config/moonraker.conf"; then
            if ask_yn "Would you like to add Klipper-Backup to moonraker update manager?"; then
                tput cup $(($questionline - 2)) 0
                tput ed
                pos1=$(getcursor)
                loading_wheel "${Y}●${NC} Adding Klipper-Backup to update manager" &
                loading_pid=$!
                ### add new line to conf if it doesn't end with one
                if [[ $(tail -c1 "$HOME/punisher_data/config/moonraker.conf" | wc -l) -eq 0 ]]; then
                    echo "" >>"$HOME/punisher_data/config/moonraker.conf"
                fi

                if /usr/bin/env bash -c "cat $parent_path/install-files/moonraker.conf >> $HOME/punisher_data/config/moonraker.conf"; then
                    sudo systemctl restart moonraker-punisher.service
                fi

                kill $loading_pid
                echo -e "\r\033[K${G}●${NC} Adding Klipper-Backup to update manager ${G}Done!${NC}\n"
            else
                tput cup $(($questionline - 2)) 0
                tput ed
                echo -e "\r\033[K${M}●${NC} Adding Klipper-Backup to update manager ${M}skipped!${NC}\n"
            fi
        else
            tput cup $(($questionline - 2)) 0
            tput ed
            echo -e "\r\033[K${M}●${NC} Adding Klipper-Backup to update manager ${M}skipped! (already added)${NC}\n"
        fi
    else
        tput cup $(($questionline - 2)) 0
        tput ed
        echo -e "${R}●${NC} Moonraker is not installed update manager configuration ${R}skipped!${NC}\n${Y}● Please install moonraker then run the script again to update the moonraker configuration${NC}\n"
    fi
}

#!/usr/bin/env bash



# --- Helper function for compiling inotify-tools (extracted & improved) ---
# This function attempts to compile and install inotify-tools from source.
# Returns 0 on success, 1 on failure.
install_inotify_from_source() {
    echo -e "\n${Y}● Compiling latest version of inotify-tools from source (This may take a few minutes)${NC}"

    # Ensure required build tools are present first
    echo "${Y}● Checking/installing build dependencies...${NC}"
    if ! sudo apt-get update || ! sudo apt-get install -y autoconf autotools-dev automake libtool build-essential git; then
         echo -e "${R}● Failed to install build dependencies via apt-get. Cannot proceed with compilation.${NC}"
         return 1
    fi
    echo "${G}● Build dependencies checked/installed.${NC}"

    local source_dir="inotify-tools-src-$$" # Temporary unique directory name
    local current_dir=$(pwd)

    # Clean up any previous source attempts just in case
    sudo rm -rf "$source_dir"

    echo "${Y}● Cloning inotify-tools repository...${NC}"
    loading_wheel "   ${Y}Cloning...${NC}" &
    local loading_pid=$!
    if git clone --depth 1 https://github.com/inotify-tools/inotify-tools.git "$source_dir" > /dev/null 2>&1; then
        kill $loading_pid &>/dev/null || true
        wait $loading_pid &>/dev/null || true # Ensure wheel process is gone
        echo -e "\r\033[K   ${G}✓ Cloning Done!${NC}"
    else
        kill $loading_pid &>/dev/null || true
        wait $loading_pid &>/dev/null || true
        echo -e "\r\033[K   ${R}✗ Failed to clone inotify-tools repository.${NC}"
        sudo rm -rf "$source_dir" # Clean up failed clone attempt
        return 1 # Indicate failure
    fi

    cd "$source_dir" || { echo -e "${R}✗ Failed to enter source directory '$source_dir'.${NC}"; sudo rm -rf "$source_dir"; return 1; }

    local build_ok=true
    local build_commands=("./autogen.sh" "./configure --prefix=/usr" "make" "sudo make install")

    for cmd in "${build_commands[@]}"; do
        echo "${Y}● Running: ${cmd}${NC}"
        # Execute command, capture output, check status
        if output=$($cmd 2>&1); then
            echo "${G}✓ Success${NC}"
        else
            echo -e "${R}✗ Command Failed: ${cmd}${NC}"
            echo -e "${R}Output:${NC}\n$output" # Show output on failure
            build_ok=false
            break # Stop build process
        fi
    done

    cd "$current_dir" # Go back to original directory
    echo "${Y}● Cleaning up source directory...${NC}"
    sudo rm -rf "$source_dir" # Clean up source directory after build attempt

    if ! $build_ok; then
         echo -e "${R}✗ Failed to compile/install inotify-tools from source.${NC}"
         return 1
    fi

    # Final check after compilation attempt
    if command -v inotifywait &> /dev/null; then
        echo -e "${G}● Successfully compiled and installed inotify-tools.${NC}"
        return 0
    else
        echo -e "${R}✗ Compilation reported success, but 'inotifywait' command still not found. Installation failed.${NC}"
        return 1
    fi
}

# --- Modified install_filewatch_service function ---
install_filewatch_service() {
    local questionline=$(getcursor)
    # Clear potential leftover lines from previous operations if needed
    # tput cup $(($questionline - 2)) 0
    local pos1=$(getcursor) # Record cursor position

    local message
    if service_exists klipper-backup-filewatch; then
        message="Would you like to reinstall the filewatch backup service? (triggers backup on config changes)"
    else
        message="Would you like to install the filewatch backup service? (triggers backup on config changes)"
    fi

    if ask_yn "$message"; then
        # Clear the prompt line(s) - adjust line count as needed (e.g., -1 for one line, -2 for two)
        tput cup $(($questionline - 1)) 0 # Go up to the line where the question started
        tput ed # Erase from cursor to end of screen

        # --- Start of new inotify-tools handling ---
        local inotify_ok=false
        echo "${Y}● Checking for required 'inotifywait' command...${NC}"
        if command -v inotifywait &> /dev/null; then
             echo -e "${G}✓ 'inotifywait' found.${NC}"
             inotify_ok=true
             sleep 0.5 # Brief pause for user to see message
        else
            echo -e "${R}✗ 'inotifywait' not found.${NC}"
            echo "${Y}● Attempting to install 'inotify-tools' via package manager...${NC}"
            # Run apt update non-interactively if possible, handle potential errors
            sudo apt-get update -qq > /dev/null 2>&1 || echo "${Y}Warning: apt-get update failed, proceeding anyway.${NC}"

            if sudo apt-get install -y inotify-tools; then
                # Verify command exists after installation
                if command -v inotifywait &> /dev/null; then
                    echo -e "${G}✓ Successfully installed 'inotify-tools' via package manager.${NC}"
                    inotify_ok=true
                else
                    # This case is unlikely but possible if package is broken or PATH is weird
                    echo -e "${R}✗ Package manager reported success, but 'inotifywait' command still not found.${NC}"
                    echo "${Y}● Falling back to compiling from source.${NC}"
                    # Attempt compilation
                    if install_inotify_from_source; then
                         inotify_ok=true
                    fi
                fi
            else
                echo -e "${R}✗ Failed to install 'inotify-tools' via package manager.${NC}"
                echo "${Y}● Falling back to compiling from source.${NC}"
                 # Attempt compilation
                 if install_inotify_from_source; then
                     inotify_ok=true
                 fi
            fi
        fi
        # --- End of new inotify-tools handling ---

        # Proceed only if inotify-tools are confirmed available
        if ! $inotify_ok; then
            echo -e "${R}✗ Failed to install or find required 'inotifywait'. Cannot install filewatch service.${NC}\n"
            # Decide whether to exit or just skip this service installation
            # exit 1 # Or just let the script continue without this service
            return 1 # Indicate failure of this function
        fi

        # --- Existing service installation logic (with minor improvements) ---
        echo "${Y}● Installing Klipper-Backup filewatch service...${NC}"
        loading_wheel "   ${Y}Installing service...${NC}" &
        local loading_pid=$!

        local install_success=false
        # Use a subshell for the installation commands to capture overall success/failure easily
        # Added error checking for each step within the subshell
        if (
            set -e # Exit subshell immediately on error
            echo "Stopping existing service (if any)..." >&2 # Log steps to stderr
            sudo systemctl stop klipper-backup-filewatch.service >/dev/null 2>&1 || true # Ignore error if not running
            echo "Copying service file..." >&2
            sudo cp "$parent_path/install-files/klipper-backup-filewatch.service" "/etc/systemd/system/klipper-backup-filewatch.service"
            echo "Patching service file..." >&2
            sudo sed -i "s/^After=.*/After=$(wantsafter)/" "/etc/systemd/system/klipper-backup-filewatch.service"
            sudo sed -i "s/^Wants=.*/Wants=$(wantsafter)/" "/etc/systemd/system/klipper-backup-filewatch.service"
            sudo sed -i "s/^User=.*/User=${SUDO_USER:-$USER}/" "/etc/systemd/system/klipper-backup-filewatch.service"
            echo "Reloading systemd daemon..." >&2
            sudo systemctl daemon-reload
            echo "Enabling service..." >&2
            sudo systemctl enable klipper-backup-filewatch.service
            echo "Starting service..." >&2
            sudo systemctl start klipper-backup-filewatch.service
            # Optional: Short pause to allow service to potentially fail immediately
            sleep 1
            # Final check if service is active
            echo "Checking service status..." >&2
            sudo systemctl is-active --quiet klipper-backup-filewatch.service
        ); then
             # Subshell succeeded
             install_success=true
        else
             # Subshell failed (due to set -e or the final status check)
             install_success=false
             # Error message will likely come from the failing command due to set -e
             echo -e "${R}✗ Service installation/start failed within subshell.${NC}" >&2
        fi

        # Stop the loading wheel regardless of success/failure
        kill $loading_pid &>/dev/null || true
        wait $loading_pid &>/dev/null || true # Wait for kill to finish

        # Check the result
        if $install_success; then
            echo -e "\r\033[K${G}✓ Installing filewatch service Done!${NC}\n"
        else
            echo -e "\r\033[K${R}✗ Failed to install or start filewatch service.${NC}\n"
            # Optional: show status for debugging
            # echo "Service status:"
            # sudo systemctl status klipper-backup-filewatch.service --no-pager || true
            return 1 # Indicate failure
        fi
        # --- End of existing service installation logic ---

    else
        # User skipped installing the service
        tput cup $(($questionline - 1)) 0 # Go up to the line where the question started
        tput ed # Erase from cursor to end of screen
        echo -e "\r\033[K${M}● Installing filewatch service skipped!${NC}\n"
    fi
    return 0 # Indicate success or skipped
}


# You need to ensure these functions are defined or sourced from utils.func
getcursor() { echo 10; } # Dummy
service_exists() { return 1; } # Dummy: Assume service doesn't exist initially
ask_yn() { read -p "$1 (y/N)? " -n 1 -r; echo; [[ $REPLY =~ ^[Yy]$ ]]; } # Basic implementation
loading_wheel() { sleep 1; } # Dummy
wantsafter() { echo "network-online.target"; } # Dummy
parent_path="." # Dummy
SUDO_USER=${SUDO_USER:-$USER} # Ensure SUDO_USER is set


install_backup_service() {
    questionline=$(getcursor)
    tput cup $(($questionline - 2)) 0
    tput ed
    pos1=$(getcursor)
    loading_wheel "${Y}●${NC} Checking for on-boot service" &
    loading_pid=$!
    if service_exists klipper-backup-on-boot; then
        echo -e "\r\033[K"
        kill $loading_pid
        message="Would you like to reinstall the on-boot backup service?"
    else
        echo -e "\r\033[K"
        kill $loading_pid
        message="Would you like to install the on-boot backup service?"
    fi
    if ask_yn "$message"; then
        tput cup $(($questionline - 2)) 0
        tput ed
        pos1=$(getcursor)
        loading_wheel "${Y}●${NC} Installing on-boot service" &
        loading_pid=$!
        if (
            !(
            sudo systemctl stop klipper-backup-on-boot.service 2>/dev/null
            sudo cp $parent_path/install-files/klipper-backup-on-boot.service /etc/systemd/system/klipper-backup-on-boot.service
            sudo sed -i "s/^After=.*/After=$(wantsafter)/" "/etc/systemd/system/klipper-backup-on-boot.service"
            sudo sed -i "s/^Wants=.*/Wants=$(wantsafter)/" "/etc/systemd/system/klipper-backup-on-boot.service"
            sudo sed -i "s/^User=.*/User=${SUDO_USER:-$USER}/" "/etc/systemd/system/klipper-backup-on-boot.service"
            sudo systemctl daemon-reload 2>/dev/null
            sudo systemctl enable klipper-backup-on-boot.service 2>/dev/null
            sudo systemctl start klipper-backup-on-boot.service 2>/dev/null
            kill $loading_pid
        ) &

            start_time=$(date +%s)
            timeout_duration=20

            while [ "$(ps -p $! -o comm=)" ]; do
                # Calculate elapsed time
                end_time=$(date +%s)
                elapsed_time=$((end_time - start_time))

                # Check if the timeout has been reached
                if [ $elapsed_time -gt $timeout_duration ]; then
                    echo -e "\r\033[K${R}●${NC} Installing on-boot service took to long to complete!\n"
                    kill $!
                    kill $loading_pid
                    exit 1
                fi

                sleep 1
            done
        ); then
            echo -e "\r\033[K${G}●${NC} Installing on-boot service ${G}Done!${NC}\n"
        fi
    else
        tput cup $(($questionline - 2)) 0
        tput ed
        echo -e "\r\033[K${M}●${NC} Installing on-boot service ${M}skipped!${NC}\n"
    fi
}

install_cron() {
    questionline=$(getcursor)
    if [ -x "$(command -v cron)" ]; then
        if ! (crontab -l 2>/dev/null | grep -q "$HOME/punisher_data/klipper-backup/script.sh"); then
            if ask_yn "Would you like to install the cron task? (automatic backup every 4 hours)"; then
                tput cup $(($questionline - 2)) 0
                tput ed
                pos1=$(getcursor)
                loading_wheel "${Y}●${NC} Installing cron task" &
                loading_pid=$!
                (
                    crontab -l 2>/dev/null
                    echo "0 */4 * * * $HOME/punisher_data/klipper-backup/script.sh -c \"Cron backup - \$(date +'\\%x - \\%X')\""
                ) | crontab -
                sleep .5
                kill $loading_pid
                echo -e "\r\033[K${G}●${NC} Installing cron task ${G}Done!${NC}\n"
            else
                tput cup $(($questionline - 2)) 0
                tput ed
                echo -e "\r\033[K${M}●${NC} Installing cron task ${M}skipped!${NC}\n"
            fi
        else
            tput cup $(($questionline - 2)) 0
            tput ed
            echo -e "\r\033[K${M}●${NC} Installing cron task ${M}skipped! (already Installed)${NC}\n"
        fi
    else
        tput cup $(($questionline - 2)) 0
        tput ed
        echo -e "\r\033[K${M}●${NC} Installing cron task ${M}skipped! (cron is not installed on system)${NC}\n"
    fi
}

if [ "$1" == "check_updates" ]; then
    check_updates
else
    main
fi
