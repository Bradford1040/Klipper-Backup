#!/usr/bin/env bash

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

show_help() {
    echo "Usage: $(basename "$0") [--config <path>]"
    echo "Converts legacy config format to current format when needed."
    echo "Exit code 0: already current format"
    echo "Exit code 10: converted from legacy format"
    echo "Exit code 1: conversion failed"
}

config_path="$scriptsh_parent_path/.env"

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
    -h | --help)
        show_help
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

# shellcheck source=/dev/null
source "$config_path"

if [[ -n "${backupPaths+x}" ]]; then
    exit 0
fi

echo "Legacy config detected. Converting: $config_path"
if "$scriptsh_parent_path/utils/v1convert.sh" --config "$config_path"; then
    exit 10
fi

echo "Legacy config conversion failed: $config_path" >&2
exit 1
