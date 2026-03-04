#!/usr/bin/env bash

trap 'stty echo; exit' SIGINT

scriptsh_parent_path=$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    cd ..
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

config_path="$scriptsh_parent_path/.env"
restore_commit_override=""

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
    --commit)
        if [[ -z "$2" || "$2" =~ ^- ]]; then
            echo "Error: commit hash expected after $1" >&2
            exit 1
        fi
        restore_commit_override="$2"
        shift 2
        ;;
    --commit=*)
        restore_commit_override="${1#*=}"
        shift
        ;;
    -h | --help)
        echo "Usage: $(basename "$0") [--config <path>] [--commit <hash>]"
        echo "If --commit is not set, an interactive commit picker is shown when run in a TTY."
        exit 0
        ;;
    *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
    esac
done

config_path="$(resolve_path "$config_path")"

if [[ ! -f "$config_path" ]]; then
    echo "Error: config file not found: $config_path" >&2
    exit 1
fi

# Initialize functions from utils
source "$scriptsh_parent_path/utils/utils.func"
source "$config_path"

envpath="$config_path"
tempfolder="/tmp/klipper-backup-restore-tmp"
temprestore="$tempfolder/klipper-backup-restore/restore.config"
restore_folder="$HOME/klipper-backup-restore"
restore_config="$restore_folder/restore.config"

ghtoken="${restore_github_token:-${github_token:-}}"
ghusername="${restore_github_username:-${github_username:-}}"
ghrepo="${restore_github_repository:-${github_repository:-}}"
ghbranch="${restore_branch_name:-${branch_name:-main}}"
ghcommithash="${restore_commit_hash:-}"

if [[ -n "$restore_commit_override" ]]; then
    ghcommithash="$restore_commit_override"
fi

git_protocol=${git_protocol:-"https"}
git_host=${git_host:-"github.com"}
ssh_user=${ssh_user:-"git"}

check_klipper_installed() {
    if ! (service_exists "klipper" && service_exists "moonraker"); then
        echo -e "${R}●${NC} Klipper and Moonraker services not found."
        exit 1
    fi
}

validate_restore_config() {
    if [[ -z "$ghrepo" || "$ghrepo" == "REPOSITORY" ]]; then
        echo -e "${R}●${NC} Missing restore repository. Set restore_github_repository or github_repository."
        exit 1
    fi

    if [[ "$git_protocol" == "ssh" ]]; then
        if [[ -z "$ghusername" || "$ghusername" == "USERNAME" ]]; then
            echo -e "${R}●${NC} Missing restore username for SSH mode."
            exit 1
        fi
    else
        if [[ -z "$ghtoken" || "$ghtoken" == "ghp_xxxxxxxxxxxxxxxx" ]]; then
            echo -e "${R}●${NC} Missing restore token. Set restore_github_token or github_token."
            exit 1
        fi

        if [[ -z "$ghusername" || "$ghusername" == "USERNAME" ]]; then
            ghusername=$(getUsername "$ghtoken")
            if [[ -z "$ghusername" ]]; then
                echo -e "${R}●${NC} restore username missing and could not be derived from token."
                exit 1
            fi
        fi
    fi

    if [[ -z "$ghbranch" ]]; then
        ghbranch="main"
    fi
}

validate_commit() {
    local commit_hash="$1"

    if [[ ! "$commit_hash" =~ ^[0-9a-f]{7,40}$ ]]; then
        return 2
    fi

    if ! git cat-file -e "$commit_hash^{commit}" 2>/dev/null; then
        return 2
    fi

    if ! git ls-tree -r "$commit_hash" --name-only | grep -q "restore.config" 2>/dev/null; then
        return 1
    fi

    git -c advice.detachedHead=false checkout "$commit_hash" >/dev/null 2>&1
    return 0
}

commit_has_restore_config() {
    local commit_hash="$1"
    git ls-tree -r "$commit_hash" --name-only | grep -q "restore.config" 2>/dev/null
}

resolve_restore_commit() {
    local commit_hash="$1"

    validate_commit "$commit_hash"
    result=$?

    if [[ $result -eq 1 ]]; then
        echo -e "${R}●${NC} Commit exists but missing restore.config: $commit_hash"
        exit 1
    elif [[ $result -eq 2 ]]; then
        echo -e "${R}●${NC} Commit does not exist: $commit_hash"
        exit 1
    fi

    ghcommithash="$commit_hash"
    echo -e "${G}●${NC} Using restore commit: $ghcommithash"
}

prompt_restore_commit_selection() {
    local selection
    local manual_hash
    local idx
    local commit_hash
    local max_candidates=15
    local scan_limit=200
    local -a candidate_commits=()
    local -a candidate_summaries=()

    while IFS= read -r commit_hash; do
        if commit_has_restore_config "$commit_hash"; then
            candidate_commits+=("$commit_hash")
            candidate_summaries+=("$(git show -s --date=local --format='%cd | %s' "$commit_hash")")
        fi

        if [[ ${#candidate_commits[@]} -ge $max_candidates ]]; then
            break
        fi
    done < <(git log --pretty=format:%H -n "$scan_limit")

    if [[ ${#candidate_commits[@]} -eq 0 ]]; then
        echo -e "${R}●${NC} No commit with restore.config found on branch '$ghbranch'."
        exit 1
    fi

    if [[ ! -t 0 || ! -t 1 ]]; then
        echo -e "${Y}●${NC} No interactive terminal detected. Using latest restore-capable commit."
        resolve_restore_commit "${candidate_commits[0]}"
        return
    fi

    echo
    echo "Select commit to restore from:"
    for idx in "${!candidate_commits[@]}"; do
        echo "  [$((idx + 1))] ${candidate_commits[$idx]:0:8}  ${candidate_summaries[$idx]}"
    done
    echo "  [m] Manual commit hash"
    echo "  [q] Abort restore"
    echo

    while true; do
        read -r -p "Choice (default 1): " selection
        selection="${selection:-1}"

        case "$selection" in
        [Qq])
            echo "Restore aborted."
            exit 1
            ;;
        [Mm])
            read -r -p "Enter commit hash: " manual_hash
            if [[ -z "$manual_hash" ]]; then
                echo "Commit hash cannot be empty."
                continue
            fi
            resolve_restore_commit "$manual_hash"
            return
            ;;
        *)
            if [[ "$selection" =~ ^[0-9]+$ ]] &&
                [[ "$selection" -ge 1 ]] &&
                [[ "$selection" -le ${#candidate_commits[@]} ]]; then
                resolve_restore_commit "${candidate_commits[$((selection - 1))]}"
                return
            fi
            echo "Invalid choice. Enter a number, 'm', or 'q'."
            ;;
        esac
    done
}

prepare_temp_repo() {
    if [[ -d "$tempfolder" ]]; then
        rm -rf "$tempfolder" 2>/dev/null
    fi

    mkdir -p "$tempfolder"

    if [[ "$git_protocol" == "ssh" ]]; then
        full_git_url="$git_protocol://$ssh_user@$git_host/$ghusername/$ghrepo.git"
    else
        full_git_url="$git_protocol://$ghtoken@$git_host/$ghusername/$ghrepo.git"
    fi

    cd "$tempfolder"
    mkdir .git
    cat > .git/config <<EOCONFIG
[init]
    defaultBranch = $ghbranch
EOCONFIG

    git init >/dev/null 2>&1
    git config pull.rebase false >/dev/null 2>&1
    git remote add origin "$full_git_url" >/dev/null 2>&1

    if ! git pull origin "$ghbranch" >/dev/null 2>&1; then
        echo -e "${R}●${NC} Failed to pull branch '$ghbranch' from $ghusername/$ghrepo."
        exit 1
    fi
}

select_restore_commit() {
    if [[ -n "$ghcommithash" ]]; then
        resolve_restore_commit "$ghcommithash"
    else
        prompt_restore_commit_selection
    fi
}

copyRestoreConfig() {
    if [[ ! -f "$temprestore" ]]; then
        echo -e "${R}●${NC} restore.config not found in selected backup state."
        exit 1
    fi

    sed -i "s/^github_token=.*/github_token=$ghtoken/" "$temprestore"
    sed -i "s/^github_username=.*/github_username=$ghusername/" "$temprestore"
    sed -i "s/^github_repository=.*/github_repository=$ghrepo/" "$temprestore"
    sed -i "s/^branch_name=.*/branch_name=\"$ghbranch\"/" "$temprestore"
    cp "$temprestore" "$envpath"
    echo -e "${G}●${NC} Rewrote runtime config from restore data."
}

restoreBackupFiles() {
    echo -e "${Y}●${NC} Restoring files"
    for path in "${backupPaths[@]}"; do
        for file in $path; do
            rsync -r --mkpath "$tempfolder/$file" "$HOME/$file"
        done
    done
    echo -e "${G}●${NC} Restoring files ${G}Done!${NC}"
}

restoreMoonrakerDB() {
    if [[ -f "$tempfolder/moonraker-db-klipperbackup.db" ]]; then
        echo -e "${Y}●${NC} Restore Moonraker Database"
        mkdir -p "$HOME/printer_data/backup/database"
        cp "$tempfolder/moonraker-db-klipperbackup.db" "$HOME/printer_data/backup/database/moonraker-db-klipperbackup.db"
        MOONRAKER_URL="http://localhost:7125"
        data='{ "filename": "moonraker-db-klipperbackup.db" }'
        curl -X POST "$MOONRAKER_URL/server/database/restore" \
            -H "Content-Type: application/json" \
            -d "$data" >/dev/null 2>&1
        echo -e "${G}●${NC} Restore Moonraker Database ${G}Done!${NC}"
    else
        echo -e "${M}●${NC} Restore Moonraker Database ${M}Skipped!${NC} (No database backup found)"
    fi
}

copyTheme() {
    if [[ -n "$theme_url" ]]; then
        echo -e "${Y}●${NC} Restoring Theme"
        cd "$HOME/printer_data/config/"
        if [[ -d ".theme" ]]; then
            rm -rf .theme
        fi
        git clone "$theme_url" .theme >/dev/null 2>&1
        if [[ -f "$tempfolder/klipper-backup-restore/theme_changes.patch" ]]; then
            cd .theme
            git apply --whitespace=nowarn "$tempfolder/klipper-backup-restore/theme_changes.patch"
        fi
        echo -e "${G}●${NC} Restoring Theme ${G}Done!${NC}"
    else
        echo -e "${M}●${NC} Restoring Theme ${M}Skipped!${NC}"
    fi
}

cleanup() {
    sed -i "s/^theme_url.*//" "$envpath"
    sed -i -e :a -e '/^\n*$/{$d;N;};/\n$/ba' "$envpath"
    sudo systemctl restart moonraker.service
    sleep 5
    sudo systemctl restart klipper.service
    echo -e "${G}●${NC} Cleaning up ${G}Done!${NC}"
}

main() {
    sudo -v
    commonDeps
    check_klipper_installed
    validate_restore_config
    prepare_temp_repo
    select_restore_commit
    copyRestoreConfig

    # shellcheck source=/dev/null
    source "$temprestore"

    sudo systemctl stop klipper.service
    restoreBackupFiles
    restoreMoonrakerDB
    copyTheme
    cleanup
}

main
