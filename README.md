# KLIPPER-BACKUP Explained for a New User

* Imagine you've spent hours, maybe even days, perfectly tuning your Klipper 3D printer configuration (printer.cfg). You've got your print speeds
* dialed in, your resonance compensation perfect, and macros set up just the way you like them. Now, what happens if the PC/Laptop updates and
* you can't fix the issue, or your Raspberry Pi fails or SD card craps out?
* Or if you accidentally delete a crucial line in your config file? You could lose all that hard work!

## What is KLIPPER-BACKUP?

* KLIPPER-BACKUP is a tool designed to solve exactly that problem. Think of it as a safety net
* for your Klipper configuration. Its main job is to:

Copy your important Klipper configuration files
(like printer.cfg, moonraker.conf, G-code files or Klipper & Moonraker logs etc.) and potentially other related files.
Store these copies safely. Track changes over time, so you can see what you changed and when.
Allow you to restore a previous version of your configuration if something goes wrong.
Protects your configuration from accidental deletion, corruption, or hardware failure.

* Version History:

See how your configuration has evolved. If a recent change causes problems, you can easily see what changed and revert it.

* Experimentation:

Try out new settings knowing you can easily go back to a working configuration if things don't work out.

* Transferring Settings:

Makes it easier to move your configuration to a new Raspberry Pi or PC/Laptop.

## How Does It Work (Conceptual Overview)?

* At its core, KLIPPER-BACKUP uses a combination of standard Linux tools:

Copying Files: It uses commands like cp or rsync to gather the files you've told it to back up from their original
locations (e.g., /home/<user_name>/<custom_name>_data/config/). Into a dedicated backup directory within the `klipper-backup` folder itself.

* Tracking Changes (Versioning):

This is where git comes in. git is a powerful version control system.

* KLIPPER-BACKUP uses git within its own directory to:

Notice which files have been added, removed, or modified since the last backup.
Record a snapshot (called a "commit") of the files at that specific moment, along with a timestamp and potentially a message.
Keep a complete history of all these snapshots.

* Remote Storage:

It is also configured to push (upload) this version history to a remote git repository service
like GitHub or GitLab. This provides an off-site backup, protecting you even if the entire Raspberry Pi or PC/Laptop is lost.

## Getting Started (Typical Steps)

* Note: These are general steps based on how such tools usually work.
* The exact commands might differ slightly based on the specific scripts in each repository.

## Crucially, review and edit the settings

* Prerequisites:

You need access to the command line (terminal/SSH) of the computer running Klipper (usually a Raspberry Pi or PC/LapTop).
You need git installed `sudo apt update && sudo apt install git`.
You might need other tools like rsync `sudo apt install rsync`, but these are often pre-installed with the (install.sh).

## Download KLIPPER-BACKUP

* Navigate to your home directory

```shell
   cd ~
```

* Clone the repository, this is a the `devel-v3.0` branch, (download it using `git clone`):

```shell
  git clone -b devel-v3.0 --single-branch https://github.com/Bradford1040/klipper-backup.git ~/klipper-backup
```

* Go into the newly downloaded custom directory:

```shell
  cd ~/klipper-backup
```

inside. This file tells the backup script what to back up and where to find it. You'll likely need to set:
The path to your `.env` configuration  (e.g., /home/<user_name>/klipper-backup or /home/<user_name>/printer_data/klipper-backup/ or
/home/<user_name>/<custom_name>_data/klipper-backup/). The klipper-backup install directory, where the files that are to be backed up are located

* Open this `shell_command.cfg`  in mainsail or fluidd to edit:

* To execute the main backup script manually. edit the `shell_command.cfg` file:

## Example of shell_command.cfg (remember when editing to remove <> as well)

```shell
[gcode_shell_command update_git_script]
command: bash /home/<user_name>/<custom_name>_data/klipper-backup/script.sh
timeout: 90.0
verbose: True
```

* Also you will need to create a Macro:

```shell
[gcode_macro BACKUP_GITHUB]
gcode:
  RUN_SHELL_COMMAND CMD=update_git_script
```

## Before we install we need to edit some files within `~/klipper-backup` directory, using a tool like (nano or Notepad++)

## We should be ready to install

```shell
./install.sh
```

## Restoring Files (Conceptual) this is in the works in (restore_dev & restore_beta branches)

The beta test for the restore function is now open, more information can be found [here](https://github.com/Staubgeborener/Klipper-Backup/discussions/143). This link is for Staubgeborener's build, which looks to be very promising!

 Restoring isn't always a single command; it often involves using git commands manually or via a dedicated restore script (if provided).

* The general idea is:

Identify the Version: Use git log within the KLIPPER-BACKUP directory to see the history of backups (commits). Each commit has a unique ID.
Find the ID of the backup you want to restore.

* Retrieve Files:

Use git checkout <commit_ID> -- <file_path> to restore a specific file
(e.g., git checkout abc123de -- klipper_config/printer.cfg) to how it was in that commit.
Be careful, this overwrites the version of the file currently in your backup directory.

* Copy Back:

Manually copy the restored file(s) from the KLIPPER-BACKUP directory back to their original
Klipper location (e.g., copy klipper_config/printer.cfg back to /home/<user_name>/klipper_config/printer.cfg).

* Restart Klipper or Moonraker:

## If you need to restart the Klipper service for the changes here is an example

```shell
sudo systemctl restart klipper-<custom_name>.service
```

## and Moonraker service example

```shell
sudo systemctl restart moonraker-<custom_name>.service
```

README.md: Documentation explaining how to use this specific version of KLIPPER-BACKUP, including any specific setup steps or features. Always read this!
.gitignore: A special git file that lists files or patterns git should ignore (like temporary files, logs within the backup dir itself, or maybe the .bak files).
.git/ (Hidden Directory): This is where git stores all the history and metadata. You generally don't need to interact with this directory directly, but it's the heart of the version control.
Directories mirroring your config: You'll likely see folders inside KLIPPER-BACKUP (e.g., klipper_config/, gcode_files/) that hold the copies of your actual configuration files after a backup runs.

* In Summary:

KLIPPER-BACKUP is your safety net. You set it up once by telling it where your Klipper config files are. Then, you run the backup script periodically
 (or maybe even automate it). It copies your files and uses git to save a snapshot, creating a history. If disaster strikes, you can use that history
  to retrieve older, working versions of your configuration.

Remember to check the README.md file within the repository for specific instructions tailored to this version of KLIPPER-BACKUP

* Good luck!
