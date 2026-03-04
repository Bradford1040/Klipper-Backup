#!/usr/bin/env bash

set -euo pipefail

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

yes_no_to_bool() {
    local value
    value=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')
    case "$value" in
    yes | y | true | 1 | on) echo "true" ;;
    *) echo "false" ;;
    esac
}

config_path="$scriptsh_parent_path/.env"

while [[ $# -gt 0 ]]; do
    case "$1" in
    --config | -config | -C)
        if [[ -z "${2:-}" || "$2" =~ ^- ]]; then
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
    -h | --help)
        echo "Usage: $(basename "$0") [--config <path>]"
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

backup_path="$config_path.bkp.$(date +%Y%m%d%H%M%S)"
cp "$config_path" "$backup_path"

# shellcheck source=/dev/null
source "$config_path"

# Build preserved non-legacy options block.
marker_line=$(grep -m 1 -n "# Individual file syntax:" "$config_path" | cut -d":" -f1 || true)
if [[ -n "$marker_line" ]]; then
    source_lines=$(head -n "$((marker_line - 1))" "$config_path")
else
    source_lines=$(cat "$config_path")
fi

config_options=""
in_backup_paths=false
in_exclude=false
while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="${line#${line%%[![:space:]]*}}"

    if [[ "$trimmed" =~ ^backupPaths=\( ]]; then
        in_backup_paths=true
        continue
    fi
    if [[ "$trimmed" =~ ^exclude=\( ]]; then
        in_exclude=true
        continue
    fi

    if $in_backup_paths || $in_exclude; then
        if [[ "$trimmed" == ")" ]]; then
            if $in_backup_paths; then
                in_backup_paths=false
            else
                in_exclude=false
            fi
        fi
        continue
    fi

    if [[ "$trimmed" =~ ^path_[^=]+= ]]; then
        continue
    fi
    if [[ "$trimmed" =~ ^extraFilewatchExclude= ]]; then
        continue
    fi
    if [[ "$trimmed" =~ ^installer_ ]]; then
        continue
    fi
    if [[ "$trimmed" =~ ^restore_ ]]; then
        continue
    fi

    if [[ "$trimmed" =~ ^empty_commit= ]]; then
        raw="${trimmed#empty_commit=}"
        line="allow_empty_commits=$(yes_no_to_bool "$raw")"
    elif [[ "$trimmed" =~ ^#.*empty_commit= ]]; then
        raw="${trimmed##*=}"
        line="#allow_empty_commits=$(yes_no_to_bool "$raw")"
    fi

    config_options+="$line"
    config_options+=$'\n'
done <<<"$source_lines"

# Build backupPaths from existing array if present; otherwise from legacy path_* entries.
legacy_paths=()
if declare -p backupPaths >/dev/null 2>&1 && [[ ${#backupPaths[@]} -gt 0 ]]; then
    legacy_paths=("${backupPaths[@]}")
else
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        legacy_paths+=("$path")
    done < <(grep -v '^#' "$config_path" | grep 'path_' | sed 's/^.*=//')
fi

backupPaths=()
for path in "${legacy_paths[@]}"; do
    # Legacy path_* entries are often quoted; normalize before processing.
    if [[ "$path" == \"*\" && "$path" == *\" ]]; then
        path="${path:1:${#path}-2}"
    elif [[ "$path" == \'*\' && "$path" == *\' ]]; then
        path="${path:1:${#path}-2}"
    fi

    [[ -z "$path" ]] && continue

    # Check if path is a directory or not a file (needed for /* checking as /* treats the path as not a directory)
    if [[ -d "$HOME/$path" && ! -f "$HOME/$path" ]]; then
        # Check if path does not end in /* or /
        if [[ ! "$path" =~ /\*$ && ! "$path" =~ /$ ]]; then
            path="$path/*"
        elif [[ ! "$path" =~ /\*$ ]]; then
            path="$path*"
        fi
    elif [[ ! "$path" =~ \* && ! "$path" =~ /$ && "$path" != *.* ]]; then
        # Heuristic for legacy directory-only entries on systems where path does not currently exist.
        path="$path/*"
    fi

    backupPaths+=("$path")
done

if [[ ${#backupPaths[@]} -eq 0 ]]; then
    backupPaths=("printer_data/config/*")
fi

if ! declare -p exclude >/dev/null 2>&1 || [[ ${#exclude[@]} -eq 0 ]]; then
    exclude=("*.swp" "*.tmp" "printer-[0-9]*_[0-9]*.cfg" "*.bak" "*.bkp" "*.csv" "*.zip")
fi

extraFilewatchExclude=${extraFilewatchExclude:-""}

installer_non_interactive=${installer_non_interactive:-true}
installer_auto_update=${installer_auto_update:-true}
installer_add_update_manager=${installer_add_update_manager:-false}
installer_install_filewatch_service=${installer_install_filewatch_service:-false}
installer_install_on_boot_service=${installer_install_on_boot_service:-false}
installer_install_cron=${installer_install_cron:-false}
installer_cron_schedule=${installer_cron_schedule:-"0 */4 * * *"}
installer_runtime_config_path=${installer_runtime_config_path:-""}

restore_github_token=${restore_github_token:-""}
restore_github_username=${restore_github_username:-""}
restore_github_repository=${restore_github_repository:-""}
restore_branch_name=${restore_branch_name:-""}
restore_commit_hash=${restore_commit_hash:-""}

{
    printf '%s' "$config_options"
    printf '%s\n' "# Backup paths"
    printf '%s\n' "# Note: script.sh starts its search in \$HOME which is /home/{username}/"
    printf '%s\n' "# The array accepts folders or files like the following example"
    printf '%s\n' "#"
    printf '%s\n' "#  backupPaths=( \\\\"
    printf '%s\n' "#  \"printer_data/config/*\" \\\\"
    printf '%s\n' "#  \"printer_data/config/printer.cfg\" \\\\"
    printf '%s\n' "#  )"
    printf '%s\n' "#"
    printf '%s\n' "# Using the above example the script will search for /home/{username}/printer_data/config/* and /home/{username}/printer_data/config/printer.cfg"
    printf '%s\n\n' "# When backing up a folder you should always have /* at the end of the path so that files inside the folder are properly searched"

    printf 'backupPaths=( \\\n'
    for path in "${backupPaths[@]}"; do
        printf '"%s" \\\n' "$path"
    done
    printf ')\n\n'

    printf '%s\n' "# Array of strings in .gitignore pattern git format https://git-scm.com/docs/gitignore#_pattern_format for files that should not be uploaded to the remote repo"
    printf '%s\n\n' "# New additions must be enclosed in double quotes and should follow the pattern format as noted in the above link"

    printf 'exclude=( \\\n'
    for extension in "${exclude[@]}"; do
        printf '"%s" \\\n' "$extension"
    done
    printf ')\n\n'

    printf '%s\n' "# String of additional filewatch excludes. names separated with a \"|\" reg-ex patterns can be used."
    printf '%s\n' "# Example extraFilewatchExclude=\"mmu_vars.cfg|macros.cfg\""
    printf 'extraFilewatchExclude="%s"\n\n' "$extraFilewatchExclude"

    printf '%s\n' "# Installer automation options (used by install.sh)"
    printf 'installer_non_interactive=%s\n' "$installer_non_interactive"
    printf 'installer_auto_update=%s\n' "$installer_auto_update"
    printf 'installer_add_update_manager=%s\n' "$installer_add_update_manager"
    printf 'installer_install_filewatch_service=%s\n' "$installer_install_filewatch_service"
    printf 'installer_install_on_boot_service=%s\n' "$installer_install_on_boot_service"
    printf 'installer_install_cron=%s\n' "$installer_install_cron"
    printf 'installer_cron_schedule="%s"\n' "$installer_cron_schedule"
    printf 'installer_runtime_config_path="%s"\n\n' "$installer_runtime_config_path"

    printf '%s\n' "# Restore automation options (used by utils/restore.sh)"
    printf '%s\n' "# If left empty, restore.sh falls back to github_* and branch_name values above."
    printf 'restore_github_token="%s"\n' "$restore_github_token"
    printf 'restore_github_username="%s"\n' "$restore_github_username"
    printf 'restore_github_repository="%s"\n' "$restore_github_repository"
    printf 'restore_branch_name="%s"\n' "$restore_branch_name"
    printf '%s\n' "# Optional commit hash to restore from."
    printf '%s\n' "# If empty and running interactively, restore prompts you to choose a commit."
    printf '%s\n' "# If empty and non-interactive, restore uses the latest commit that contains restore data."
    printf 'restore_commit_hash="%s"\n' "$restore_commit_hash"
} >"$config_path"

echo "Legacy config converted: $config_path"
echo "Backup created at: $backup_path"
