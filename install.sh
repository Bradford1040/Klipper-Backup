#!/usr/bin/env bash

trap 'stty echo; exit' SIGINT

parent_path=$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd -P
)

default_config_path="$parent_path/.env"
config_path="$default_config_path"
runtime_config_path=""
install_mode="install"
debug_output=false
original_args=("$@")

resolve_path() {
    local path="$1"
    if [[ "$path" == "~"* ]]; then
        path="${path/#\~/$HOME}"
    fi
    if [[ "$path" != /* ]]; then
        path="$(pwd)/$path"
    fi
    printf '%s\n' "$path"
}

is_true() {
    case "$1" in
    [Tt][Rr][Uu][Ee] | [Yy][Ee][Ss] | [Yy] | 1 | [Oo][Nn]) return 0 ;;
    *) return 1 ;;
    esac
}

bool_to_yes_no() {
    if is_true "$1"; then
        echo "Yes"
    else
        echo "No"
    fi
}

escape_sed_replacement() {
    printf '%s' "$1" | sed -e 's/[&|]/\\&/g'
}

upsert_config_unquoted() {
    local key="$1"
    local value="$2"
    local escaped_value
    escaped_value=$(escape_sed_replacement "$value")
    if grep -q "^${key}=" "$config_path"; then
        sed -i "s|^${key}=.*|${key}=${escaped_value}|" "$config_path"
    else
        echo "${key}=${value}" >>"$config_path"
    fi
}

upsert_config_quoted() {
    local key="$1"
    local value="$2"
    local escaped_value
    local append_value
    escaped_value=$(escape_sed_replacement "$value")
    escaped_value="${escaped_value//\"/\\\"}"
    append_value="${value//\"/\\\"}"
    if grep -q "^${key}=" "$config_path"; then
        sed -i "s|^${key}=.*|${key}=\"${escaped_value}\"|" "$config_path"
    else
        echo "${key}=\"${append_value}\"" >>"$config_path"
    fi
}

show_install_help() {
    echo "Usage: $(basename "$0") [OPTION]..."
    echo
    echo "Options:"
    echo "  -C, --config, -config [PATH]   use a custom config file"
    echo "  -r, --restore                  run restore utility using config"
    echo "  --convert-legacy               convert legacy config format to current format"
    echo "  check_updates                  check/update repository only"
    echo "  -d, --debug                    enable debug output"
    echo "  -h, --help                     display this help and exit"
    echo
    echo "Examples:"
    echo "  $(basename "$0") --config /path/to/backup.env"
    echo "  $(basename "$0") --convert-legacy --config /path/to/legacy.env"
    echo "  $(basename "$0") --restore --config /path/to/backup.env"
}

parse_install_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -C | --config | -config)
            if [[ -z "$2" || "$2" =~ ^- ]]; then
                echo "Error: config path expected after $1" >&2
                exit 1
            fi
            config_path="$2"
            shift 2
            ;;
        -C=* | --config=* | -config=*)
            config_path="${1#*=}"
            shift
            ;;
        check_updates)
            install_mode="check_updates"
            shift
            ;;
        --restore | -r)
            install_mode="restore"
            shift
            ;;
        --convert-legacy)
            install_mode="convert_legacy"
            shift
            ;;
        -d | --debug)
            debug_output=true
            shift
            ;;
        -h | --help)
            show_install_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_install_help >&2
            exit 1
            ;;
        esac
    done
}

parse_install_args "$@"

if [[ "$config_path" == "$default_config_path" && ! -f "$default_config_path" ]]; then
    cp "$parent_path/.env.example" "$default_config_path"
fi

config_path="$(resolve_path "$config_path")"

if [[ ! -f "$config_path" ]]; then
    echo "Error: config file not found: $config_path" >&2
    exit 1
fi

if [[ "$install_mode" == "convert_legacy" ]]; then
    exec "$parent_path/utils/v1convert.sh" --config "$config_path"
fi

if [[ "$install_mode" == "restore" ]]; then
    exec "$parent_path/utils/restore.sh" --config "$config_path"
fi

source "$parent_path/utils/utils.func"
source "$config_path"

installer_auto_update=${installer_auto_update:-true}
installer_add_update_manager=${installer_add_update_manager:-false}
installer_install_filewatch_service=${installer_install_filewatch_service:-false}
installer_install_on_boot_service=${installer_install_on_boot_service:-false}
installer_install_cron=${installer_install_cron:-false}
installer_cron_schedule=${installer_cron_schedule:-"0 */4 * * *"}

if [[ -n "${installer_runtime_config_path:-}" ]]; then
    runtime_config_path="$(resolve_path "$installer_runtime_config_path")"
else
    runtime_config_path="$config_path"
fi

restart_args=(--config "$config_path")
unique_id=$(getUniqueid)

ensure_current_config_version() {
    "$parent_path/utils/ensure_config_version.sh" --config "$config_path"
    config_version_status=$?
    if [[ $config_version_status -eq 10 ]]; then
        # shellcheck source=/dev/null
        source "$config_path"
    elif [[ $config_version_status -ne 0 ]]; then
        echo -e "${R}●${NC} Legacy config conversion failed."
        exit 1
    fi
}

check_updates() {
    cd ~/klipper-backup || {
        echo -e "${R}●${NC} ~/klipper-backup not found."
        return 1
    }

    if [ "$(git rev-parse HEAD)" = "$(git ls-remote $(git rev-parse --abbrev-ref @{u} | sed 's/\// /g') | cut -f1)" ]; then
        echo -e "${G}●${NC} Klipper-Backup is up to date."
        return 0
    fi

    echo -e "${Y}●${NC} Update for Klipper-Backup available."

    if is_true "$installer_auto_update"; then
        if git pull >/dev/null 2>&1; then
            echo -e "${G}●${NC} Updating Klipper-Backup ${G}Done!${NC}"
            exec "$parent_path/install.sh" "${restart_args[@]}"
        else
            echo -e "${R}●${NC} Error updating Klipper-Backup. Resolve local git changes and retry."
            exit 1
        fi
    else
        echo -e "${M}●${NC} Auto-update ${M}Skipped!${NC}"
    fi
}

install_update() {
    cd "$HOME"

    if [[ ! -d "klipper-backup/.git" ]]; then
        echo -e "${Y}●${NC} Installing Klipper-Backup"
        if ! git clone https://github.com/Staubgeborener/klipper-backup.git >/dev/null 2>&1; then
            echo -e "${R}●${NC} Failed to clone Klipper-Backup repository."
            exit 1
        fi
        chmod +x ./klipper-backup/script.sh
        if [[ ! -f ./klipper-backup/.env ]]; then
            cp ./klipper-backup/.env.example ./klipper-backup/.env
        fi
        echo -e "${G}●${NC} Installing Klipper-Backup ${G}Done!${NC}"
    else
        check_updates
    fi
}

configure() {
    local ghtoken ghusername ghrepo ghbranch commitname commitemail

    ghtoken="${github_token:-}"
    ghusername="${github_username:-}"
    ghrepo="${github_repository:-}"
    ghbranch="${branch_name:-main}"
    commitname="${commit_username:-}"
    commitemail="${commit_email:-}"

    git_protocol=${git_protocol:-"https"}

    if [[ -z "$ghrepo" || "$ghrepo" == "REPOSITORY" ]]; then
        echo -e "${R}●${NC} Missing github_repository in config: $config_path"
        exit 1
    fi

    if [[ "$git_protocol" != "ssh" ]]; then
        if [[ -z "$ghtoken" || "$ghtoken" == "ghp_xxxxxxxxxxxxxxxx" ]]; then
            echo -e "${R}●${NC} Missing github_token in config: $config_path"
            exit 1
        fi

        if [[ -z "$ghusername" || "$ghusername" == "USERNAME" ]]; then
            ghusername=$(getUsername "$ghtoken")
            if [[ -z "$ghusername" ]]; then
                echo -e "${R}●${NC} github_username missing and could not be derived from token."
                exit 1
            fi
        fi
    else
        if [[ -z "$ghusername" || "$ghusername" == "USERNAME" ]]; then
            echo -e "${R}●${NC} Missing github_username for SSH mode."
            exit 1
        fi
    fi

    if [[ -z "$ghbranch" ]]; then
        ghbranch="main"
    fi

    if [[ -z "$commitname" ]]; then
        commitname="$(whoami)"
    fi

    if [[ -z "$commitemail" ]]; then
        commitemail="$(whoami)@$(hostname --short)-$unique_id"
    fi

    upsert_config_unquoted "github_token" "$ghtoken"
    upsert_config_unquoted "github_username" "$ghusername"
    upsert_config_unquoted "github_repository" "$ghrepo"
    upsert_config_unquoted "branch_name" "$ghbranch"
    upsert_config_quoted "commit_username" "$commitname"
    upsert_config_quoted "commit_email" "$commitemail"

    echo -e "${G}●${NC} Configuration ${G}Done!${NC}"
}

set_optional_actions() {
    if is_true "$installer_add_update_manager"; then
        if [[ -d $HOME/moonraker ]] && systemctl is-active moonraker >/dev/null 2>&1; then
            if ! grep -Eq "^\[update_manager klipper-backup\]\s*$" "$HOME/printer_data/config/moonraker.conf"; then
                moonrakerManager="Yes"
                moonrakerMsg="${CL}${G}●${NC} Adding klipper-backup to update manager ${G}Done!${NC}"
            else
                moonrakerManager="No"
                moonrakerMsg="${CL}${M}●${NC} Adding klipper-backup to update manager ${M}Skipped! (Already Added)${NC}"
            fi
        else
            moonrakerManager="No"
            moonrakerMsg="${R}●${NC} Moonraker is not installed. Update manager configuration ${R}Skipped!${NC}"
        fi
    else
        moonrakerManager="No"
        moonrakerMsg="${CL}${M}●${NC} Adding klipper-backup to update manager ${M}Skipped!${NC}"
    fi

    installFilewatch=$(bool_to_yes_no "$installer_install_filewatch_service")
    installService=$(bool_to_yes_no "$installer_install_on_boot_service")

    if crontab -l 2>/dev/null | grep -q "$HOME/klipper-backup/script.sh"; then
        installCron="No"
        cronMsg="${CL}${M}●${NC} Installing cron task ${M}Skipped! (Already Installed)${NC}"
    else
        installCron=$(bool_to_yes_no "$installer_install_cron")
    fi
}

patch_klipper-backup_update_manager() {
    if [[ $moonrakerManager == "Yes" ]]; then
        loading_wheel "${Y}●${NC} Adding klipper-backup to update manager" &
        loading_pid=$!
        if [[ $(tail -c1 "$HOME/printer_data/config/moonraker.conf" | wc -l) -eq 0 ]]; then
            echo "" >>"$HOME/printer_data/config/moonraker.conf"
        fi

        if /usr/bin/env bash -c "cat $parent_path/install-files/moonraker.conf >> $HOME/printer_data/config/moonraker.conf"; then
            sudo systemctl restart moonraker.service
        fi

        kill $loading_pid
    fi

    echo -e "$moonrakerMsg"
}

install_filewatch_service() {
    if [[ $installFilewatch == "Yes" ]]; then
        if ! checkinotify >/dev/null 2>&1; then
            removeOldInotify
            echo -e "${Y}●${NC} Installing latest version of inotify-tools (this may take a few minutes)"
            sudo rm -rf inotify-tools/
            sudo rm -f /usr/bin/fsnotifywait /usr/bin/fsnotifywatch
            loading_wheel "   ${Y}●${NC} Clone inotify-tools repo" &
            loading_pid=$!
            git clone https://github.com/inotify-tools/inotify-tools.git >/dev/null 2>&1
            kill $loading_pid
            echo -e "${CL}   ${G}●${NC} Clone inotify-tools repo ${G}Done!${NC}"
            sudo apt-get install autoconf autotools-dev automake libtool -y >/dev/null 2>&1

            cd inotify-tools/
            buildCommands=("./autogen.sh" "./configure --prefix=/usr" "make" "make install")
            for ((i = 0; i < ${#buildCommands[@]}; i++)); do
                run_command "${buildCommands[i]}"
            done
            cd ..
            sudo rm -rf inotify-tools
            echo -e "${CL}${G}●${NC} Installing latest version of inotify-tools ${G}Done!${NC}"
        fi

        loading_wheel "${Y}●${NC} Installing filewatch service" &
        loading_pid=$!
        sudo systemctl stop klipper-backup-filewatch.service >/dev/null 2>&1 || true
        sudo cp "$parent_path/install-files/klipper-backup-filewatch.service" /etc/systemd/system/klipper-backup-filewatch.service
        sudo sed -i "s/^After=.*/After=$(wantsafter)/" "/etc/systemd/system/klipper-backup-filewatch.service"
        sudo sed -i "s/^Wants=.*/Wants=$(wantsafter)/" "/etc/systemd/system/klipper-backup-filewatch.service"
        sudo sed -i "s/^User=.*/User=${SUDO_USER:-$USER}/" "/etc/systemd/system/klipper-backup-filewatch.service"

        escaped_runtime_config=$(escape_sed_replacement "$runtime_config_path")
        if ! grep -q "^Environment=KLIPPER_BACKUP_CONFIG=" "/etc/systemd/system/klipper-backup-filewatch.service"; then
            sudo sed -i "/^Type=.*/a Environment=KLIPPER_BACKUP_CONFIG=" "/etc/systemd/system/klipper-backup-filewatch.service"
        fi
        sudo sed -i "s|^Environment=KLIPPER_BACKUP_CONFIG=.*|Environment=\"KLIPPER_BACKUP_CONFIG=$escaped_runtime_config\"|" "/etc/systemd/system/klipper-backup-filewatch.service"

        sudo systemctl daemon-reload >/dev/null 2>&1
        sudo systemctl enable klipper-backup-filewatch.service >/dev/null 2>&1
        sudo systemctl start klipper-backup-filewatch.service >/dev/null 2>&1
        kill $loading_pid
        echo -e "${CL}${G}●${NC} Installing filewatch service ${G}Done!${NC}"
    else
        echo -e "${CL}${M}●${NC} Installing filewatch service ${M}Skipped!${NC}"
    fi
}

install_backup_service() {
    if [[ $installService == "Yes" ]]; then
        loading_wheel "${Y}●${NC} Installing on-boot service" &
        loading_pid=$!
        sudo systemctl stop klipper-backup-on-boot.service >/dev/null 2>&1 || true
        sudo cp "$parent_path/install-files/klipper-backup-on-boot.service" /etc/systemd/system/klipper-backup-on-boot.service
        sudo sed -i "s/^After=.*/After=$(wantsafter)/" "/etc/systemd/system/klipper-backup-on-boot.service"
        sudo sed -i "s/^Wants=.*/Wants=$(wantsafter)/" "/etc/systemd/system/klipper-backup-on-boot.service"
        sudo sed -i "s/^User=.*/User=${SUDO_USER:-$USER}/" "/etc/systemd/system/klipper-backup-on-boot.service"

        escaped_runtime_config=$(escape_sed_replacement "$runtime_config_path")
        if ! grep -q "^Environment=KLIPPER_BACKUP_CONFIG=" "/etc/systemd/system/klipper-backup-on-boot.service"; then
            sudo sed -i "/^Type=.*/a Environment=KLIPPER_BACKUP_CONFIG=" "/etc/systemd/system/klipper-backup-on-boot.service"
        fi
        sudo sed -i "s|^Environment=KLIPPER_BACKUP_CONFIG=.*|Environment=\"KLIPPER_BACKUP_CONFIG=$escaped_runtime_config\"|" "/etc/systemd/system/klipper-backup-on-boot.service"

        sudo systemctl daemon-reload >/dev/null 2>&1
        sudo systemctl enable klipper-backup-on-boot.service >/dev/null 2>&1
        sudo systemctl start klipper-backup-on-boot.service >/dev/null 2>&1
        kill $loading_pid
        echo -e "${CL}${G}●${NC} Installing on-boot service ${G}Done!${NC}"
    else
        echo -e "${CL}${M}●${NC} Installing on-boot service ${M}Skipped!${NC}"
    fi
}

install_cron() {
    if [[ $installCron == "Yes" ]]; then
        loading_wheel "${Y}●${NC} Installing cron task" &
        loading_pid=$!

        local cron_command
        local existing_cron
        local filtered_cron

        cron_command="$HOME/klipper-backup/script.sh --config \"$runtime_config_path\" -c \"Cron backup - \\$(date +'\\%x - \\%X')\""
        existing_cron=$(crontab -l 2>/dev/null || true)
        filtered_cron=$(printf "%s\n" "$existing_cron" | grep -vF "$HOME/klipper-backup/script.sh" || true)

        {
            if [[ -n "$filtered_cron" ]]; then
                printf "%s\n" "$filtered_cron"
            fi
            printf "%s %s\n" "$installer_cron_schedule" "$cron_command"
        } | crontab -

        kill $loading_pid
        cronMsg="${CL}${G}●${NC} Installing cron task ${G}Done!${NC}"
    else
        if [[ -z "$cronMsg" ]]; then
            cronMsg="${CL}${M}●${NC} Installing cron task ${M}Skipped!${NC}"
        fi
    fi

    echo -e "$cronMsg"
}

main() {
    sudo -v
    commonDeps
    ensure_current_config_version
    install_update
    configure
    set_optional_actions
    patch_klipper-backup_update_manager
    install_filewatch_service
    install_backup_service
    install_cron
    echo -e "${G}●${NC} Installation Complete!"
    echo -e "${G}●${NC} Runtime config: $runtime_config_path"
}

if [[ "$debug_output" == true ]]; then
    source "$parent_path/utils/install-debug.func"
    debug_install_context
fi

if [[ "$install_mode" == "check_updates" ]]; then
    check_updates
else
    main
fi
