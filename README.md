# Web Sync Deploy

Fast, private deployments over SSH using `rsync`, with SFTP available for basic transfers. The script runs every enabled deployment from `web-sync.config.json` without asking for a final confirmation.

## Requirements

- Bash
- `jq` to read the JSON config
- For `"method": "ssh"`: `ssh` and `rsync`
- For `"method": "sftp"`: `sftp`
- `sshpass` only when an SSH password is configured and unsafe mode is enabled
- `base64` and `tr` only when a sudo password is configured and unsafe mode is enabled
- `sed` to read `.gitignore` patterns (the script creates `.gitignore` if it is missing)

The script checks the required commands at startup and reports missing dependencies together.

## First run

```bash
./web-sync.sh
```

If `web-sync.config.json` does not exist, the script creates a starter config and exits. It also ensures the config filename is in the project `.gitignore`, creating `.gitignore` if needed. Edit the JSON, then run the script again.

## Configuration

Each item under `deploys` is one source-to-destination mapping. `enable` accepts `true`/`false` or `1`/`0`. Disabled items are skipped. If omitted, `enable` defaults to `true`.

```json
{
  "server": "your-server.com",
  "user": "your-ssh-user",
  "method": "ssh",
  "unsafe_mode": false,
  "ssh_password": "",
  "sudo_password": "",
  "remote_chown": "www-data:www-data",
  "remote_dir_mode": "755",
  "remote_file_mode": "644",
  "remote_sudo": true,
  "remote_staging_root": "/home/your-ssh-user/.web-sync-staging",
  "deploys": {
    "site-1": {
      "enable": true,
      "source": "docs-output/site-1",
      "dest": "/var/www/site-1",
      "type": "static"
    },
    "site-2": {
      "enable": true,
      "source": "docs-output/site-2",
      "dest": "/var/www/site-2",
      "type": "static"
    }
  }
}
```

Relative `source` paths are resolved from the directory containing `web-sync.sh`. Supported deployment `type` values are `static`, `laravel`, and `webkernel`.

Set `method` to `ssh` or `sftp`. SSH uses rsync and runs the configured Laravel/WebKernel post-deploy commands. SFTP performs a basic file transfer and does not run those commands.

### Passwords and sudo

SSH and sudo passwords are ignored unless `unsafe_mode` is `true` or `1`. Passwords stored in JSON are plain text. SSH keys and passwordless sudo are preferable. When `sudo_password` is used, the script temporarily creates a remote askpass helper inside the staging directory to publish staged files with sudo.

## Run

```bash
./web-sync.sh
```

All enabled deployment entries run automatically. rsync displays its live transfer progress. Status messages use color in a terminal; set `NO_COLOR` to disable colors.

## Sync behavior

- Excludes `.git` and applies patterns from the project `.gitignore`.
- For Laravel and WebKernel deployments, also excludes `.env` and `bootstrap/cache/`.
- SSH deployments can apply remote permissions and ownership.
- Static deployments do not run framework commands.
- Laravel and WebKernel deployments run Composer update, migrations, and Laravel cache commands after transfer.

## License

MPL-2.0

**El Moumen Yassine**
