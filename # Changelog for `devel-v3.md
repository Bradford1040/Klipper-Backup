# Changelog: main vs devel-v3.0

* This summarizes the significant changes introduced between the `main` branch and the `devel-v3.0` branch.

## Added

* User Repository Check: Implemented a check during the backup process to verify user-created repositories.
* Contextual Prompts: Added more informative messages to ask_yn confirmation prompts (utils.func).
* Shell Command Configuration: Added functionality to create or append to shell_command.cfg during installation.
* Inotify & Lock Service: Added installation of inotify-tools (from source) and a lock service to prevent conflicts between manual and scheduled backups.
* Documentation: Added information about the custom installation file to the README.
* Changelog: Added an changelog file (tracking changes since main).

### Changed

* Branch Targeting: Updated the installation script and internal references to target/use devel-v3.0 instead of KIAUH_V1/KIAUH_V2.
* Cron Job Installation: Modified the cron job setup to run on every script execution to ensure it's correctly scheduled.
* Rsync Options: Changed rsync -Rr to rsync -aR for potentially more robust backup behavior.
* Script/Folder Structure: Refactored folder locations for file and boot scripts (associated with KIAUH_V1 changes).
* Line Endings: Converted file line endings from CRLF to LF for better Unix compatibility.
* Code Refinements: Numerous cleanups, including removing extra spaces, fixing formatting, refactoring functions, and improving code structure.
* Major Refactoring: Included significant unspecified changes described as "Major change, too much to list".
* Gitignore: Updated .gitignore to exclude vscode suggestions and remove python/node.js entries.
* CI/Development: Updated markdown_issue_check.yaml, added ShellCheck integration, and included Original Developer links.
* Backup Path: Added more flexibility/options to the backup path configuration.
* README: Multiple updates including version changes, added mentions, clarifications, and removal of unnecessary lines.
* Installation Script: General updates and improvements to install.sh.

### Fixed

* Directory Navigation: Corrected cd command logic for navigating relative to the home directory.
* Sed Command: Fixed an error in a sed command used within a script.
* Systemd Service Files:
  * Added missing network dependency checks (After=network-online.target Wants=network-online.target).
  * Corrected service file naming conventions (e.g., filewatch, backup-on-boot, moonraker-custom_name.service).
  * Added missing WorkingDirectory directives.
  * Added missing [update_manager client devel-v3.0] entry reference for Moonraker configuration.
* Script Syntax/Logic:
  * Fixed misplaced if/else/fi statements.
  * Fixed incorrectly placed #!/bin/bash shebang.
  * Fixed incorrect bash syntax in dependency checks (... vs :;).
  * Fixed a trap command mistake.
  * Fixed an exit error on a specific line (910).
  * Fixed various terminal output errors (including removing tput usage).
  * Fixed accidentally included/pasted lines.
* Configuration: Fixed the backup path specified in .env.example.
* Typos/Spelling: Corrected various spelling errors in code comments and documentation (README).
* Markdown Formatting: Removed extraneous whitespace from shell code blocks in markdown files.

### Removed

* Extraneous whitespace characters from various files.
* tput command usage due to terminal issues.
* Incorrect bash language identifiers (... instead of :;).
* Accidentally pasted lines of code.
* python & node.js from .gitignore!
