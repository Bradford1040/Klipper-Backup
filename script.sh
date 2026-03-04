#!/usr/bin/env bash

# set dotglob so that bash treats hidden files/folders starting with . correctly when copying them (ex. .themes from mainsail)
shopt -s dotglob

parent_path=$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd -P
)

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

parse_config_arg() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --config | -config | -C)
            if [[ -z "$2" || "$2" =~ ^- ]]; then
                echo "Error: config path expected after $1" >&2
                exit 1
            fi
            config_path="$2"
            shift 2
            ;;
        --config=* | -config=* | -C=*)
            config_path="${1#*=}"
            shift
            ;;
        *)
            shift
            ;;
        esac
    done
}

init() {
    config_path="$parent_path/.env"
    original_args=("$@")
    args="$*"

    parse_config_arg "$@"
    config_path="$(resolve_path "$config_path")"

    if [[ ! -f "$config_path" ]]; then
        echo "Error: config file not found: $config_path" >&2
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$config_path"
    source "$parent_path/utils/utils.func"

    # Do not touch these variables, the .env file and the documentation exist for this purpose
    backup_folder="config_backup"
    backup_path="$HOME/$backup_folder"
    backup_restore_data="$HOME/klipper-backup-restore"
    moonraker_db_backups=${moonraker_db_backups:-false}
    theme_path="$HOME/printer_data/config/.theme"
    allow_empty_commits=${allow_empty_commits:-true}
    use_filenames_as_commit_msg=${use_filenames_as_commit_msg:-false}
    git_protocol=${git_protocol:-"https"}
    git_host=${git_host:-"github.com"}
    ssh_user=${ssh_user:-"git"}

    if [[ $git_protocol == "ssh" ]]; then
        full_git_url="$git_protocol://$ssh_user@$git_host/$github_username/$github_repository.git"
    else
        full_git_url="$git_protocol://$github_token@$git_host/$github_username/$github_repository.git"
    fi

    exclude=${exclude:-"*.swp" "*.tmp" "printer-[0-9]*_[0-9]*.cfg" "*.bak" "*.bkp" "*.csv" "*.zip"}

    commit_message_used=false
    debug_output=false

    set -- "${original_args[@]}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -h | --help)
            show_help
            exit 0
            ;;
        -f | --fix)
            fix
            shift
            ;;
        -c | --commit_message)
            if [[ -z "$2" || "$2" =~ ^- ]]; then
                echo -e "${CL}${R}Error: commit message expected after $1${NC}" >&2
                exit 1
            fi
            commit_message="$2"
            commit_message_used=true
            shift 2
            ;;
        -d | --debug)
            debug_output=true
            shift
            ;;
        --config | -config | -C)
            if [[ -z "$2" || "$2" =~ ^- ]]; then
                echo -e "${CL}${R}Error: config path expected after $1${NC}" >&2
                exit 1
            fi
            shift 2
            ;;
        --config=* | -config=* | -C=*)
            shift
            ;;
        *)
            echo -e "${CL}${R}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
        esac
    done

    "$parent_path/utils/ensure_config_version.sh" --config "$config_path"
    config_version_status=$?
    if [[ $config_version_status -eq 10 ]]; then
        echo "Upgrade complete restarting script.sh"
        sleep 2.5
        exec "$parent_path/script.sh" "${original_args[@]}"
    elif [[ $config_version_status -ne 0 ]]; then
        exit 1
    fi

    if [[ "$debug_output" == true ]]; then
        source "$parent_path/utils/debug.func"
    fi
}

checkUpdates() {
    [ "$(git -C "$parent_path" rev-parse HEAD)" = "$(git -C "$parent_path" ls-remote $(git -C "$parent_path" rev-parse --abbrev-ref @{u} | sed 's/\// /g') | cut -f1)" ] &&
        echo -e "Klipper-Backup is up to date\n" ||
        echo -e "${Y}●${NC} Update for Klipper-Backup ${Y}Available!${NC}\n"
}

createBackupFolder() {
    if [[ ! -d "$backup_path" ]]; then
        mkdir -p "$backup_path"
    fi

    cd "$backup_path"

    if [[ ! -d ".git" ]]; then
        mkdir .git
        echo "[init]
    defaultBranch = $branch_name" >>.git/config
        git init
        git config pull.rebase false
    elif [[ $(git symbolic-ref --short -q HEAD) != "$branch_name" ]]; then
        echo -e "Branch: $branch_name in .env does not match the currently checked out branch of: $(git symbolic-ref --short -q HEAD)."
        if git show-ref --quiet --verify "refs/heads/$branch_name"; then
            git checkout "$branch_name" >/dev/null
        else
            git checkout -b "$branch_name" >/dev/null
        fi
    fi

    if [[ -z "$(git remote get-url origin 2>/dev/null)" ]]; then
        git remote add origin "$full_git_url"
    fi

    if [[ "$full_git_url" != "$(git remote get-url origin)" ]]; then
        git remote set-url origin "$full_git_url"
    fi

    if git ls-remote --exit-code --heads origin "$branch_name" >/dev/null 2>&1; then
        git pull origin "$branch_name"
        find "$backup_path" -maxdepth 1 -mindepth 1 ! -name '.git' ! -name '.gitmodules' ! -name 'README.md' -exec rm -rf {} \;
    fi
}

checkEnv() {
    if [[ "$commit_username" != "" ]]; then
        git config user.name "$commit_username"
    else
        git config user.name "$(whoami)"
        sed -i "s/^commit_username=.*/commit_username=\"$(whoami)\"/" "$config_path"
    fi

    if [[ "$commit_email" != "" ]]; then
        git config user.email "$commit_email"
    else
        unique_id=$(date +%s%N | md5sum | head -c 7)
        user_email="$(whoami)@$(hostname --short)-$unique_id"
        git config user.email "$user_email"
        sed -i "s/^commit_email=.*/commit_email=\"$user_email\"/" "$config_path"
    fi
}

copyFiles() {
    cd "$HOME"

    bash "$parent_path/utils/create_restore_data.sh" --config "$config_path"
    rsync -Rr "${backup_restore_data##"$HOME"/}" "$backup_path"
    rm -rf "$backup_restore_data"

    for path in "${backupPaths[@]}"; do
        fullPath="$HOME/$path"
        if [[ -d "$fullPath" && ! -f "$fullPath" ]]; then
            if [[ "$path" =~ /$ ]]; then
                backupPaths[$i]="$path*"
            elif [[ -d "$path" ]]; then
                backupPaths[$i]="$path/*"
            fi
        fi

        if compgen -G "$fullPath" >/dev/null; then
            for file in $path; do
                if [[ -h "$file" ]]; then
                    echo "Skipping symbolic link: $file"
                elif [[ -n "$(find "$file" -regex '.*/\.git*' 2>/dev/null)" ]]; then
                    echo ".git folder: $file detected, don't add back to backup"
                else
                    file=$(readlink -e "$file")
                    rsync -Rr "${file##"$HOME"/}" "$backup_path"
                fi
            done
        fi
    done

    cp "$parent_path/.gitignore" "$backup_path/.gitignore"

    if $moonraker_db_backups; then
        echo -e "Backup Moonraker DB"
        MOONRAKER_URL="http://localhost:7125"
        data='{ "filename": "moonraker-db-klipperbackup.db" }'
        if curl -X POST "$MOONRAKER_URL/server/database/backup" \
            -H "Content-Type: application/json" \
            -d "$data" >/dev/null 2>&1; then
            cp "$HOME/printer_data/backup/database/moonraker-db-klipperbackup.db" "$backup_path/moonraker-db-klipperbackup.db"
        else
            echo -e "Database Backup Failed - Is the printer printing?"
        fi
    fi

    for i in ${exclude[@]}; do
        [[ $(tail -c1 "$backup_path/.gitignore" | wc -l) -eq 0 ]] && echo "" >>"$backup_path/.gitignore"
        echo "$i" >>"$backup_path/.gitignore"
    done
}

pre-commitCleanup() {
    cd "$backup_path"

    if ! [[ -f "README.md" ]]; then
        cat >"$backup_path/README.md" <<'EOFREADME'
# Klipper-Backup 💾
Klipper backup script for manual or automated GitHub backups.

This backup is provided by [Klipper-Backup](https://github.com/Staubgeborener/klipper-backup).
EOFREADME
    fi

    git rm -r --cached . >/dev/null 2>&1

    if [[ -n "$(git -C "$theme_path" remote get-url origin 2>/dev/null)" ]]; then
        url=$(git -C "$theme_path" remote get-url origin)
        git -C "$backup_path" submodule add -f "$url" printer_data/config/.theme
    fi
}

pushCommit() {
    if ! $commit_message_used; then
        commit_message="New backup from $(date +"%x - %X")"
    fi

    if $use_filenames_as_commit_msg; then
        commit_message=$(git diff --name-only "$branch_name" | xargs -n 1 basename | tr '\n' ' ')
    fi

    git add .
    git commit -m "$commit_message"

    if $allow_empty_commits && [[ $(git rev-parse HEAD) == $(git ls-remote $(git rev-parse --abbrev-ref @{u} 2>/dev/null | sed 's/\// /g') | cut -f1) ]]; then
        git commit --allow-empty -m "$commit_message - No new changes pushed"
    fi

    git push -u origin "$branch_name"
}

cleanUp() {
    find "$backup_path" -maxdepth 1 -mindepth 1 ! -name '.git' ! -name '.gitmodules' ! -name 'README.md' -exec rm -rf {} \;
}

main() {
    loading_wheel "${Y}●${NC} Checking for installed dependencies" &
    loading_pid=$!
    commonDeps
    kill $loading_pid
    echo -e "${CL}${G}●${NC} Checking for installed dependencies ${G}Done!${NC}\n"

    checkUpdates
    createBackupFolder
    checkEnv
    copyFiles

    cd "$backup_path"
    pre-commitCleanup
    pushCommit
    cleanUp
}

init "$@"
main
