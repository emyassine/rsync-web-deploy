# rsync-web-deploy

Fast, private deployment using `rsync`.
No Git on server.

---

## Install

```bash
git clone https://github.com/emyassine/rsync-web-deploy.git
mv rsync-web-deploy/web-sync.sh .
chmod +x web-sync.sh
````

---

## Ignore deploy files (IMPORTANT)

In the **target project** `.gitignore`:

```gitignore
web-sync.sh
web-sync.config
```

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

---

## Deploy

```bash
./web-sync.shweb-sync.sh
```

Choose instance → choose method → deploy.

---

## What it does

* Sync current directory via `rsync`
* Respects `.gitignore`
* Excludes `.git`, `.env`, caches
* SSH or SFTP

### SSH only

* `composer install --no-dev`
* `php artisan migrate --force`
* Cache optimize

---

## Requirements

* bash
* rsync
* ssh
* php + composer (Laravel / WebKernel)

---

## License

MPL-2.0

**El Moumen Yassine**
