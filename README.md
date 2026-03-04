# ANNOUNCEMENT
The beta test for the restore function is now open, more information can be found [here](https://github.com/Staubgeborener/Klipper-Backup/discussions/143).

# Klipper-Backup 💾
Klipper-Backup is a script for manual or automated GitHub backups. It's Lightweight, pragmatic and comfortable.

## Installation

### Download:
```shell
curl -fsSL get.klipperbackup.xyz | bash
```

### Installation/Configuration:
```shell
~/klipper-backup/install.sh
```

### Config-Driven / Automated Usage
Create a config file (for example from `.env.example`), set all values once, then pass it to scripts:

```shell
~/klipper-backup/install.sh --config /path/to/backup.env
~/klipper-backup/script.sh --config /path/to/backup.env
~/klipper-backup/install.sh --restore --config /path/to/backup.env
```

Restore commit selection behavior:
- set `restore_commit_hash` (or pass `--commit`) for fully non-interactive restore pinning.
- leave `restore_commit_hash` empty to get an interactive commit picker in a terminal.
- in non-interactive environments, empty `restore_commit_hash` falls back to the latest valid restore commit.

`-config` is also accepted as an alias for `--config`.

The installer is fully config-driven; configure the `installer_*` options in the config file.

### Legacy Config Conversion
If you have an old/legacy config format, convert it in-place with:

```shell
~/klipper-backup/install.sh --convert-legacy --config /path/to/legacy.env
```

A timestamped backup of the legacy file is created automatically.

## RTFM
I would suggest reading the [docs](https://klipperbackup.xyz), as this provides detailed step-by-step instructions and further tips such as an [FAQ](https://klipperbackup.xyz/faq/).

## YouTube
There are several YouTube videos about Klipper-Backup - thanks to everyone!

* [Chris Riley: Klipper Backup - Save Your Klipper Config - Before You Lose It! - Chris's Basement](https://www.youtube.com/watch?v=RCWWtzrI-e8)

* [ModBot: This Klipper Add-on Could Save You! (Klipper-Backup)](https://www.youtube.com/watch?v=47qV9BE2n_Y)

* [Minimal 3DP: The Ultimate Guide to Using Klipper Macros to Backup Your Configuration Files](https://www.youtube.com/watch?v=J4_dlCtZY48)
