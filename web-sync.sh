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
#   Edit web-sync.config before first use
#

set -euo pipefail

CONFIG_FILE="./web-sync.config"
GITIGNORE_FILE=".gitignore"

create_default_config() {
cat > "$CONFIG_FILE" << 'EOF'
# ============================================================
# Web Sync Deploy – Configuration File
# ============================================================
# This file defines the remote server and deployment instances.
# Each instance maps a local deployment name to:
#
#   /remote/path:context
#
# Available contexts:
#   - webkernel : WebKernel-based applications
#   - laravel   : Standard Laravel applications
#   - static    : Static websites (HTML/CSS/JS only)
#
# Example:
#   ["Production"]="/var/www/app:webkernel"
# ============================================================

# Remote server hostname or IP
SERVER="your-server.com"

# SSH user used for deployment
USER="your-username"

# ------------------------------------------------------------
# Deployment instances
# ------------------------------------------------------------
# Format:
#   ["InstanceName"]="/absolute/remote/path:context"
# ------------------------------------------------------------

declare -A INSTANCES=(
  ["Production"]="/var/www/production:webkernel"
  ["Staging"]="/var/www/staging:webkernel"
  ["Static"]="/var/www/static:static"
)

# ------------------------------------------------------------
# Deployment methods
# ------------------------------------------------------------
# ssh  : Recommended (rsync + post-deploy tasks)
# sftp : Basic transfer only (no context-aware actions)
# ------------------------------------------------------------

METHODS=("ssh" "sftp")

# ============================================================
# End of configuration
# ============================================================
EOF

  echo "Default configuration created at $CONFIG_FILE"
  echo "Edit this file with your server and paths, then run the script again."
  exit 0
}

build_rsync_excludes() {
  local context="$1"
  local excludes="--exclude='.git'"

  case $context in
    webkernel|laravel)
      excludes="$excludes --exclude='.env' --exclude='bootstrap/cache/'"
      ;;
  esac

  if [[ -f "$GITIGNORE_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [[ -z "$line" || "$line" =~ ^# ]] && continue
      excludes="$excludes --exclude='$line'"
    done < "$GITIGNORE_FILE"
  fi

  echo "$excludes"
}

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

[[ ! -f "$CONFIG_FILE" ]] && create_default_config

source "$CONFIG_FILE"

echo ""
echo ""
echo "WEB SYNC (•) DEPLOY"
echo "Fast Private Alternative to Git Push"
echo "Intelligent sync with gitignore respect, excludes .git,"
echo "optimized transfers, and interactive deployment"
echo ""
echo "<rsync optimization> <gitignore> <interactive> <secure>"
echo "<Deploy> <Backup> <Sync> <Transfer> <Production Ready>"
echo "<WebKernel> <Laravel> <Static> <Context Aware> <Permissions>"
echo ""
echo ""
echo "Server: $SERVER"
echo "User: $USER"
echo ""

if [[ ${#INSTANCES[@]} -eq 0 ]]; then
  echo "No instances configured"
  exit 1
fi

echo "Available instances:"
declare -a instance_names
declare -a instance_paths
declare -a instance_contexts
i=1
for name in "${!INSTANCES[@]}"; do
  IFS=':' read -r path context <<< "${INSTANCES[$name]}"
  echo "$i) $name -> $path [$context]"
  instance_names[$i]=$name
  instance_paths[$i]=$path
  instance_contexts[$i]=$context
  ((i++))
done
echo ""

read -p "Choose instance [1-${#instance_names[@]}]: " choice

if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 ]] || [[ $choice -gt ${#instance_names[@]} ]]; then
  echo "Invalid choice"
  exit 1
fi

INSTANCE=${instance_names[$choice]}
TARGET=${instance_paths[$choice]}
CONTEXT=${instance_contexts[$choice]}

echo ""
echo "Available methods:"
for i in "${!METHODS[@]}"; do
  echo "$((i+1))) ${METHODS[$i]}"
done
echo ""

read -p "Choose method [1-${#METHODS[@]}]: " method_choice

if [[ ! "$method_choice" =~ ^[0-9]+$ ]] || [[ $method_choice -lt 1 ]] || [[ $method_choice -gt ${#METHODS[@]} ]]; then
  echo "Invalid choice"
  exit 1
fi

METHOD=${METHODS[$((method_choice-1))]}
SOURCE="$PWD/"
HOST="$USER@$SERVER"

echo ""
echo "Deploying $SOURCE to $INSTANCE [$CONTEXT] via $METHOD..."
echo ""

case $METHOD in
  ssh)
    EXCLUDES=$(build_rsync_excludes "$CONTEXT")
    eval rsync -avz --delete --progress --no-perms --no-owner --no-group $EXCLUDES "$SOURCE" "$HOST:$TARGET/"

    run_post_deploy "$HOST" "$TARGET" "$CONTEXT"
    ;;
  sftp)
    echo "WARNING: SFTP does not support context-aware deployment"
    echo "Use SSH method for WebKernel/Laravel projects"
    echo ""
    read -p "Continue anyway? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Deployment cancelled"
      exit 0
    fi
    sftp "$HOST" <<EOF
cd $TARGET
put -r $SOURCE/*
EOF
    ;;
  *)
    echo "Unknown method: $METHOD"
    exit 1
    ;;
esac

echo ""
echo "Deployment completed successfully"
echo ""
exit 0
