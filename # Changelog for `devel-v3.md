# Changelog for `devel-v3.0`

> There has been 14 commits between `devel-v3.0` and `KIAUH_V2`

----

## Added

- Adds a check to verify user-created repositories.
- Adds a message to `ask_yn` in `utils.func` to provide more context.

### Changed

- Updates the cron install process to run on each install, ensuring proper scheduling.
- Changes the install script to use `devel-v3.0` instead of `KIAUH_V2`.

### Fixed

- Fixes an issue where `cd` to home directory would not go up one folder.
- Fixes a mistake in `sed` command within a script.
- Fixes missing network checks in example services.
- Fixes incorrect names for `filewatch` and `backup on boot` services.
- Fixes missing `devel-v3.0` entry in `moonraker.conf` and `WorkingDirectory` entries in `filewatch` and `backup-on-boot` services.

### Removed

- Removes extra spaces from shell code markdown.

### P.S. I plan to add a full change log from the `main` branch
