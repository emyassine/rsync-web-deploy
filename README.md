# rsync-web-deploy

Fast, private deployment script using `rsync`.
No Git on server. No CI. No bullshit.

---

## Install

```bash
git clone https://github.com/emyassine/rsync-web-deploy.git
cd rsync-web-deploy
chmod +x web-sync.sh
````

---

## First run (generate config)

```bash
./web-sync.sh
```

This creates `web-sync.config`.

---

## Configure

Edit `web-sync.config`:

```bash
SERVER="your-server.com"
USER="your-ssh-user"

declare -A INSTANCES=(
  ["Production"]="/var/www/app:webkernel"
  ["Staging"]="/var/www/app-staging:laravel"
  ["Static"]="/var/www/static:static"
)

METHODS=("ssh" "sftp")
```

**Contexts**

* `webkernel`
* `laravel`
* `static`

---

## Deploy

```bash
./web-sync.sh
```

Then:

1. Choose instance
2. Choose method
3. Deploy

---

## What it does

* Syncs current directory to server with `rsync`
* Respects `.gitignore`
* Excludes `.git`, `.env`, cache dirs
* Uses SSH or SFTP

### Post-deploy (SSH only)

* `composer install --no-dev`
* `php artisan migrate --force`
* Cache optimizations

---

## Requirements

* Bash
* rsync
* SSH access
* Composer + PHP (for Laravel / WebKernel)

---

## License

MPL-2.0

El Moumen Yassine
