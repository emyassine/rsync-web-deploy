#!/bin/bash
#
# Web Sync Deploy
#
# Fast, private, context-aware deployment script using rsync.
# Designed as an alternative to git push for production environments.
#
# Features:
# - SSH / SFTP deployment
# - Respects .gitignore exclusions
# - Multiple deployment instances
# - Context-aware post-deployment (WebKernel, Laravel, Static)
# - Optimized transfers with rsync
#
# Author: El Moumen Yassine
# License: MPL-2.0
#
# Usage:
#   ./web-sync.sh
#
# Configuration:
#   Edit web-sync.config.json before first use
#

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/web-sync.config.json"
GITIGNORE_FILE="$SCRIPT_DIR/.gitignore"

BASE_DEPENDENCIES=(jq)
SSH_DEPENDENCIES=(ssh rsync)
SFTP_DEPENDENCIES=(sftp)
SSH_PASSWORD_DEPENDENCIES=(sshpass)
SUDO_PASSWORD_DEPENDENCIES=(base64 tr)
GITIGNORE_DEPENDENCIES=(sed)

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_BLUE=$'\033[34m'
  C_CYAN=$'\033[36m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
else
  C_RESET=''
  C_BOLD=''
  C_BLUE=''
  C_CYAN=''
  C_GREEN=''
  C_YELLOW=''
  C_RED=''
fi

say_info() { printf '%s•%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
say_step() { printf '\n%s▶%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
say_success() { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
say_warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
say_error() { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

check_dependencies() {
  local dependency
  local -a missing=()

  for dependency in "$@"; do
    command -v "$dependency" >/dev/null 2>&1 || missing+=("$dependency")
  done

  if (( ${#missing[@]} )); then
    say_error "Missing required dependencies: ${missing[*]}"
    exit 1
  fi
}

ensure_config_file_is_in_gitignore() {
  local config_entry="${CONFIG_FILE##*/}"
  local ignore_line
  local last_line=""
  local found=false

  [[ -f "$GITIGNORE_FILE" ]] || : > "$GITIGNORE_FILE"

  while IFS= read -r ignore_line || [[ -n "$ignore_line" ]]; do
    last_line="$ignore_line"
    if [[ "$ignore_line" == "$config_entry" || "$ignore_line" == "/$config_entry" ]]; then
      found=true
    fi
  done < "$GITIGNORE_FILE"

  if [[ "$found" != true ]]; then
    [[ -z "$last_line" ]] || printf '\n' >> "$GITIGNORE_FILE"
    printf '%s\n' "$config_entry" >> "$GITIGNORE_FILE"
  fi
}

create_default_config() {
cat > "$CONFIG_FILE" << 'EOF'
{
  "server": "your-server.com",
  "user": "your-username",
  "method": "ssh",
  "unsafe_mode": false,
  "ssh_password": "",
  "sudo_password": "",
  "remote_chown": "",
  "remote_sudo": false,
  "remote_staging_root": "$HOME/.web-sync-staging",
  "deploys": {
    "Production": {
      "enable": true,
      "source": ".",
      "dest": "/var/www/production",
      "type": "webkernel"
    }
  }
}
EOF
  say_success "Created default JSON configuration: $CONFIG_FILE"
  say_info "Edit the config, then run the script again."
  exit 0
}

build_rsync_excludes() {
  local context="$1"
  local -a excludes=(--exclude=.git)

  case $context in
    webkernel|laravel)
      excludes+=(--exclude=.env --exclude=bootstrap/cache/)
      ;;
  esac

  if [[ -f "$GITIGNORE_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [[ -z "$line" || "$line" =~ ^# ]] && continue
      excludes+=(--exclude="$line")
    done < "$GITIGNORE_FILE"
  fi

  RSYNC_EXCLUDES=("${excludes[@]}")
}

RSYNC_EXCLUDES=()

run_post_deploy() {
  local host="$1"
  local target="$2"
  local context="$3"

  case $context in
    webkernel)
      echo ""
      echo "Running WebKernel post-deployment tasks..."
      ssh "$host" "cd $target && composer update --no-dev --optimize-autoloader && php artisan migrate --force && php artisan config:cache && php artisan route:cache && php artisan view:cache"
      ;;
    laravel)
      echo ""
      echo "Running Laravel post-deployment tasks..."
      ssh "$host" "cd $target && composer update --no-dev --optimize-autoloader && php artisan migrate --force && php artisan config:cache && php artisan route:cache && php artisan view:cache"
      ;;
    static)
      echo ""
      echo "Static site deployed, no post-deployment tasks needed"
      ;;
  esac
}

ensure_config_file_is_in_gitignore
[[ ! -f "$CONFIG_FILE" ]] && create_default_config

check_dependencies "${BASE_DEPENDENCIES[@]}"
jq -e 'type == "object" and (.deploys | type == "object")' "$CONFIG_FILE" >/dev/null || {
  say_error "Invalid JSON config or missing deploys object: $CONFIG_FILE"
  exit 1
}

SERVER=$(jq -r '.server // empty' "$CONFIG_FILE")
USER=$(jq -r '.user // empty' "$CONFIG_FILE")
METHOD=$(jq -r '.method // "ssh"' "$CONFIG_FILE")
UNSAFE_MODE=$(jq -r '.unsafe_mode // false' "$CONFIG_FILE")
SSH_PASSWORD=$(jq -r '.ssh_password // ""' "$CONFIG_FILE")
SUDO_PASSWORD=$(jq -r '.sudo_password // ""' "$CONFIG_FILE")
REMOTE_CHOWN=$(jq -r '.remote_chown // ""' "$CONFIG_FILE")
REMOTE_DIR_MODE=$(jq -r '.remote_dir_mode // "755"' "$CONFIG_FILE")
REMOTE_FILE_MODE=$(jq -r '.remote_file_mode // "644"' "$CONFIG_FILE")
RSYNC_REMOTE_SUDO=$(jq -r '.remote_sudo // false' "$CONFIG_FILE")
REMOTE_STAGING_ROOT=$(jq -r '.remote_staging_root // "~/.web-sync-staging"' "$CONFIG_FILE")
[[ -n "$SERVER" && -n "$USER" ]] || { say_error "Config requires server and user"; exit 1; }
[[ "$METHOD" == "ssh" || "$METHOD" == "sftp" ]] || { say_error "Unsupported method: $METHOD"; exit 1; }
if [[ "$UNSAFE_MODE" != "true" && "$UNSAFE_MODE" != "1" ]]; then
  SSH_PASSWORD=""
  SUDO_PASSWORD=""
fi

DEPENDENCIES=("${BASE_DEPENDENCIES[@]}")
case "$METHOD" in
  ssh) DEPENDENCIES+=("${SSH_DEPENDENCIES[@]}") ;;
  sftp) DEPENDENCIES+=("${SFTP_DEPENDENCIES[@]}") ;;
esac
if [[ -n "$SSH_PASSWORD" ]]; then DEPENDENCIES+=("${SSH_PASSWORD_DEPENDENCIES[@]}"); fi
if [[ -n "$SUDO_PASSWORD" ]]; then DEPENDENCIES+=("${SUDO_PASSWORD_DEPENDENCIES[@]}"); fi
if [[ -f "$GITIGNORE_FILE" ]]; then DEPENDENCIES+=("${GITIGNORE_DEPENDENCIES[@]}"); fi
check_dependencies "${DEPENDENCIES[@]}"

echo ""
echo ""
printf '%s%sWEB SYNC (•) DEPLOY%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
printf '%sFast Private Alternative to Git Push\n' "$C_CYAN"
printf 'Intelligent sync with gitignore respect, excludes .git,\n'
printf 'optimized transfers, and interactive deployment%s\n' "$C_RESET"
printf '%s────────────────────────────────────────%s\n' "$C_BLUE" "$C_RESET"
say_info "Target: $USER@$SERVER"
say_info "Method: $METHOD"
echo ""

HOST="$USER@$SERVER"

if [[ -n "$SSH_PASSWORD" ]]; then
  export SSHPASS="$SSH_PASSWORD"
  ssh() { command sshpass -e ssh "$@"; }
  rsync() { command sshpass -e rsync -e "sshpass -e ssh" "$@"; }
fi

say_step "Checking configured deployments"
enabled_deploys=$(jq -r '.deploys | to_entries[] | select(if (.value | has("enable")) then (.value.enable == true or .value.enable == 1) else true end) | [.key, .value.source, .value.dest, .value.type] | @tsv' "$CONFIG_FILE")
[[ -n "$enabled_deploys" ]] || { say_error "No enabled deployments configured"; exit 1; }
while IFS=$'\t' read -r INSTANCE source_input TARGET CONTEXT; do
  if [[ -z "$source_input" || -z "$TARGET" || -z "$CONTEXT" ]]; then
    say_error "Deployment '$INSTANCE' requires source, dest, and type"; exit 1
  fi
  if [[ "$source_input" = /* ]]; then SOURCE="$source_input"; else SOURCE="$SCRIPT_DIR/$source_input"; fi
  if [[ ! -d "$SOURCE" ]]; then say_error "Source directory does not exist: $SOURCE"; exit 1; fi
  SOURCE="$(cd -- "$SOURCE" && pwd)/"

  say_step "$INSTANCE · $CONTEXT"
  say_info "Source: ${SOURCE%/}"
  say_info "Destination: $TARGET"
  say_info "Preparing transfer via $METHOD"
  case $METHOD in
  ssh)
    build_rsync_excludes "$CONTEXT"
    if [[ -n "${REMOTE_CHOWN:-}" ]]; then
      if [[ ! "${REMOTE_CHOWN}" =~ ^[^:]+:[^:]+$ ]]; then
        echo "REMOTE_CHOWN must use owner:group form, for example yassine:www-data"
        exit 1
      fi
      if [[ "${RSYNC_REMOTE_SUDO:-false}" != "true" ]]; then
        echo "REMOTE_CHOWN requires RSYNC_REMOTE_SUDO=true"
        exit 1
      fi
    fi
    if [[ "${RSYNC_REMOTE_SUDO:-false}" == "true" ]]; then
      stage_instance="${INSTANCE//[^A-Za-z0-9_.-]/_}"
      remote_stage="${REMOTE_STAGING_ROOT%/}/$stage_instance"
      printf -v remote_stage_q '%q' "$remote_stage"
      printf -v remote_target_q '%q' "$TARGET"
      ssh "$HOST" "mkdir -p -- $remote_stage_q"
      say_info "Uploading files to remote staging directory"
      rsync -avz --progress --no-perms --no-owner --no-group "${RSYNC_EXCLUDES[@]}" "$SOURCE" "$HOST:$remote_stage/"

      printf -v remote_chmod_arg '%q' "D${REMOTE_DIR_MODE:-755},F${REMOTE_FILE_MODE:-644}"
      sudo_prefix="sudo"
      if [[ -n "$SUDO_PASSWORD" ]]; then
        encoded_sudo_password="$(printf '%s' "$SUDO_PASSWORD" | base64 | tr -d '\n')"
        askpass_path="$remote_stage/.askpass"
        ssh "$HOST" "mkdir -p -- $remote_stage_q && printf '%s' '$encoded_sudo_password' | base64 -d > '$askpass_path' && chmod 700 '$askpass_path'"
        sudo_prefix="SUDO_ASKPASS=$askpass_path sudo -A"
      fi
      publish_command="$sudo_prefix rsync -av --ignore-times --chmod=$remote_chmod_arg"
      if [[ -n "${REMOTE_CHOWN:-}" ]]; then
        printf -v remote_chown_arg '%q' "--chown=$REMOTE_CHOWN"
        publish_command+=" $remote_chown_arg"
      fi
      publish_command+=" -- $remote_stage_q/ $remote_target_q/"
      say_info "Publishing staged files to destination"
      ssh -tt "$HOST" "$publish_command"
      ssh "$HOST" "rm -rf -- $remote_stage_q"
    else
      rsync_options=(--chmod="D${REMOTE_DIR_MODE:-755},F${REMOTE_FILE_MODE:-644}")
      rsync_identity_options=(--no-owner --no-group)
      say_info "Syncing files (live rsync progress follows)"
      rsync -avz --progress "${rsync_identity_options[@]}" "${rsync_options[@]}" "${RSYNC_EXCLUDES[@]}" "$SOURCE" "$HOST:$TARGET/"
    fi

    run_post_deploy "$HOST" "$TARGET" "$CONTEXT"
    ;;
  sftp)
    if [[ -n "${REMOTE_CHOWN:-}" || "${RSYNC_REMOTE_SUDO:-false}" == "true" ]]; then
      echo "SFTP cannot apply REMOTE_CHOWN, remote sudo, or configured permissions. Select SSH (rsync) instead."
      exit 1
    fi
    say_warn "SFTP does not support context-aware deployment"
    sftp "$HOST" <<EOF
cd $TARGET
put -r ${SOURCE%/}/*
EOF
    ;;
  *)
    echo "Unknown method: $METHOD"
    exit 1
    ;;
esac
done <<< "$enabled_deploys"

say_success "All enabled deployments completed successfully"
exit 0
