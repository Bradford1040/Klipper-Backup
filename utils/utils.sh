#!/usr/bin/env bash

export R=$'\033[1;91m' # Red ${R}
export G=$'\033[1;92m' # Green ${G}
export Y=$'\033[1;93m' # Yellow ${Y}
export M=$'\033[1;95m' # Magenta ${M}
export C=$'\033[96m'   # Cyan ${C}
export NC=$'\033[0m'   # No Color ${NC}


# Create unique id for git email
getUniqueid() {
	date +%s%N | md5sum | head -c 7;
} # Simple unique ID

wantsafter() {
    if dpkg -l | grep -q '^ii.*network-manager' && systemctl is-active --quiet "NetworkManager"; then
        echo "NetworkManager-wait-online.service"
    else
        echo "network-online.target"
    fi
}

is_ssh() {
    [[ -n "$SSH_CONNECTION" || -n "$SSH_TTY" ]]
}

loading_wheel() {
    local chars="/-\|"
    local delay=0.1
    local message="$*" # Use "$*" for clarity when assigning all args to a single string
    if is_ssh; then
        # Simpler animation for SSH: just dots
        echo -n "$message"
        while true; do
            echo -n "."
            sleep 0.5
        done
    else
        tput civis
        while true; do
            for i in {0..3}; do
                echo -ne "\r${chars:$i:1} $message"
                sleep $delay
            done
        done
        # tput cnorm was here, but it's unreachable due to the infinite loop.
        # Cursor restoration (tput cnorm) should be handled by the script
        # that backgrounds and then kills this loading_wheel.
    fi
}

getcursor() {
	tput cup 999 0; 
	echo -ne "\033[6n"; 
	read -rsdR CURPOS; CURPOS=${CURPOS#*[}; 
	echo "${CURPOS%;*}"; 
} # stronger getcursor

run_command() {
    command=$1
    loading_wheel "   ${Y}●${NC} Running $command" &
    loading_pid=$!
    sudo "$command" >/dev/null 2>&1
    kill $loading_pid
    echo -e "\r\033[K   ${G}●${NC} Running $command ${G}Done!${NC}"
}

clearUp() {
	tput ed; 
} # Clear from cursor to end of screen

logo() {
    clear
    echo -e "${C}$(
        cat <<"EOF"
    __ __ ___                             ____             __                     ____           __        ____
   / //_// (_)___  ____  ___  _____      / __ )____ ______/ /____  ______        /  _/___  _____/ /_____ _/ / /
  / ,<  / / / __ \/ __ \/ _ \/ ___/_____/ __  / __ `/ ___/ //_/ / / / __ \______ / // __ \/ ___/ __/ __ `/ / /
 / /| |/ / / /_/ / /_/ /  __/ /  /_____/ /_/ / /_/ / /__/ ,< / /_/ / /_/ /_____// // / / (__  ) /_/ /_/ / / /
/_/ |_/_/_/ .___/ .___/\___/_/        /_____/\__,_/\___/_/|_|\__,_/ .___/     /___/_/ /_/____/\__/\__,_/_/_/
         /_/   /_/                                               /_/
EOF
    )${NC}"
    echo ""
    echo "==============================================================================================================="
    echo ""
}

ask_yn() {
    local prompt="$1";
    local response;
    # Add the reminder text to the prompt string
    local full_prompt="$prompt (y/N - Enter accepts 'N')? "
    while true; do
        # Use the modified prompt
        read -p "$full_prompt" -n 1 -r response < /dev/tty; echo; # -n 1 reads only one char
        clear # clear screen after each input
        case "$response" in
        [yY]) return 0;;
        [nN]|"") return 1;; # "" handles the Enter key press, defaulting to No
        *) echo "Please answer yes or no.";;
        esac;
    done;
}

ask_token() {
    local prompt="$1: "
    local input=""
    echo -n "$prompt" >&2
    stty -echo # Disable echoing of characters
    while IFS= read -rs -n 1 char; do
        if [[ $char == $'\0' || $char == $'\n' ]]; then
            break
        elif [[ $char == $'\177' ]]; then # Check for backspace character
            if [ -n "$input" ]; then      # Check if input is not empty
                input=${input%?}          # Remove last character from input
                echo -en "\b \b" >&2      # Move cursor back, overwrite with space, move cursor back again
            fi
        else
            input+=$char
            echo -n "*" >&2 # Explicitly echo asterisks to stderr
        fi
    done
    stty echo # Re-enable echoing
    echo >&2  # Move to a new line after user input
    echo "$input"
}

ask_textinput() {
	local prompt="$1"; 
	local default="$2"; 
	local response; 
		read -rp "$prompt [$default]: " response < /dev/tty; 
		echo "${response:-$default}"; 
} # Basic text input

# Function to move the cursor to a specific position
function move_cursor() {
    echo -e "\033[${1};${2}H"
}

# Function to display the menu and return status codes
function menu() {
    choice=1
    # Define the starting row for the menu. Assumed to be 1 as 'clear' is typically called before 'menu'.
    local menu_start_row=1
    while true; do
        # Highlight the current choice
        if [ "$choice" -eq 1 ]; then
            echo -e "\e[7m1. Confirm\e[0m"
            echo "2. Re-enter"
        else
            echo "1. Confirm"
            echo -e "\e[7m2. Re-enter\e[0m"
        fi

        read -rsn 1 key

        case $key in
        [1-2]) # Number keys 1 and 2
            choice=$key
            ;;
        A) # Up arrow
            if [ "$choice" -eq 2 ]; then
                ((choice--))
            fi
            ;;
        B) # Down arrow
            if [ "$choice" -eq 1 ]; then
                ((choice++))
            fi
            ;;
        "") # Enter key
            case $choice in
            1)
                clear # Clear screen on Confirm
                return 0
                ;;
            2)
                return 1
                ;;
            esac
            ;;
        esac

        move_cursor "$menu_start_row" 0

    done
}

check_ghToken() {
    GITHUB_TOKEN="$1"
    API_URL="https://api.github.com/user"

    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" $API_URL)

    if [[ $response =~ "message" ]]; then
        ghtoken_username=""
        echo "$ghtoken_username"
    else
        ghtoken_username=$(echo "$response" | jq -r '.login')
        echo "$ghtoken_username"
    fi
}

service_exists() {
    systemctl list-units --full -all | grep -q "$1.service"; 
} # Basic service check

checkinotify() {
    local_version=$(inotifywait -h | grep -oP '\d+\.\d+\.\d+\.\d+')
    # Get the latest release information from the GitHub repository
    latest_release=$(curl -s "https://api.github.com/repos/inotify-tools/inotify-tools/releases/latest")
    # Extract the latest release version number
    latest_version=$(echo "$latest_release" | jq -r '.tag_name')

    # Compare the installed version with the latest version
    if [[ $local_version == "$latest_version" ]]; then
        return 0 #Local matches latest
    else
        return 1 #Local does not match latest
    fi
}

check_dependencies() {
    for pkg in "$@"; do
        if ! command -v "$pkg" &>/dev/null; then
            # Check the package manager and attempt a silent install
            if command -v apt-get &>/dev/null; then
                sudo apt-get update >/dev/null
                sudo apt-get install -y "$pkg" >/dev/null 2>&1
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y "$pkg" >/dev/null 2>&1
            elif command -v pacman &>/dev/null; then
                sudo pacman -S --noconfirm "$pkg" >/dev/null 2>&1
            elif command -v apk &>/dev/null; then
                sudo apk add "$pkg" >/dev/null 2>&1
            else
                echo "Unsupported package manager. Please install '$pkg' manually."
                return 1
            fi
            # Check if the installation was successful
            if ! dpkg -s "$pkg" >/dev/null 2>&1; then
                echo "Installation failed. Please install '$pkg' manually."
                return 1
            fi
        fi
    done
}

removeOldInotify() {
    oldInotify=("inotifywait" "libinotifytools0" "libinotifytools0-dev")
    for pkg in "${oldInotify[@]}"; do
        # Check the package manager and attempt a silent install
        if command -v apt-get &>/dev/null; then
            sudo apt remove -y "$pkg" >/dev/null 2>&1
        elif command -v dnf &>/dev/null; then
            sudo dnf remove -y "$pkg" >/dev/null 2>&1
        elif command -v pacman &>/dev/null; then
            sudo pacman -Rs --noconfirm "$pkg" >/dev/null 2>&1
        elif command -v apk &>/dev/null; then
            sudo apk remove "$pkg" >/dev/null 2>&1
        else
            echo "Unsupported package manager. Please remove inotify-tools manually."
            return 1
        fi
    done
}

show_help(){
    echo "Usage: $(basename "$0") [OPTION]..."
    echo "Klipper-Backup is a script for manual or automated Klipper GitHub backups. It's Lightweight, pragmatic and comfortable."
    echo "https://github.com/Bradford1040/klipper-backup/tree/devel-v3.0"
    echo "https://klipperbackup.xyz"
    echo
    echo "Options:"
    echo "  -h, --help                     display this help and exit"
    echo "  -c, --commit_message [TEXT]    use your own commit message for the git push"
    echo "  -f, --fix                      delete the config_backup folder. This can help to solve the vast majority of error messages"
    echo "  -d, --debug                    debugging output"
    echo
    echo "Examples:"
    echo "  $(basename "$0") --help"
    echo "  $(basename "$0") --commit_message \"My own commit message\""
    echo "  $(basename "$0") --fix"
    echo "  $(basename "$0") --debug"
}

begin_debug_line(){
    echo -e "\n------------DEBUG:------------"
}

end_debug_line(){
    echo -e "------------------------------\n"
}
