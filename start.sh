#!/bin/bash
# Railway launcher. The image's own ENTRYPOINT (deploy/docker/entrypoint.sh)
# still runs — it copies local_settings.py into place, creates the app
# directories and chowns the tree — and then execs this as CMD, exactly where
# the stock deploy/docker/start.sh used to sit.
#
# Everything here has to happen before prestart.sh copies the nginx and
# supervisord files into /etc, which is what the real start.sh does first.
set -e

APP=/home/mediacms.io/mediacms
SEED=/opt/railway/media_seed
cd "$APP"

log() { echo "[railway] $*"; }

# --- 1. seed the assets the image ships inside media_files -------------------
# A Railway volume mounted at media_files hides the default avatar, banner and
# audio poster that live in the image, so copy them back. -n never overwrites,
# so an operator's replacements survive every redeploy.
if [ -d "$SEED" ]; then
    mkdir -p "$APP/media_files"
    cp -rn "$SEED"/* "$APP/media_files/" 2>/dev/null || true
    log "media_files now holds: $(ls -A "$APP/media_files" | tr '\n' ' ')"
fi
mkdir -p "$APP/media_files/hls" "$APP/media_files/original" "$APP/media_files/encoded"
chown -R www-data:www-data "$APP/media_files"

# --- 2. nginx: listen on Railway's PORT --------------------------------------
# The shipped config hardcodes :80. Railway probes and routes the port named by
# PORT, and gunicorn is bound to 127.0.0.1:9000 where no prober can reach it, so
# nginx is what has to move.
PORT="${PORT:-8080}"
NGINX_SITE=deploy/docker/nginx_http_only.conf
sed -i -E "s/listen[[:space:]]+80[[:space:]]*;/listen ${PORT};/" "$NGINX_SITE"
if ! grep -q "listen ${PORT};" "$NGINX_SITE"; then
    log "FATAL: could not rewrite the nginx listen directive in $NGINX_SITE"
    exit 1
fi
log "nginx will listen on ${PORT}"

# --- 3. nginx: trust Railway's edge so $remote_addr is the real client -------
# The edge arrives from 100.64.0.0/10 and appends its own public 152.233.0.0/17
# address to X-Forwarded-For, so a right-to-left walk needs all three ranges
# trusted before it lands on the caller. nginx.conf already includes
# conf.d/*.conf from its http block, so this needs no edit to a shipped file.
mkdir -p /etc/nginx/conf.d
cat > /etc/nginx/conf.d/railway-realip.conf <<'REALIP'
# Railway edge ranges. real_ip_recursive walks X-Forwarded-For right to left and
# stops on the first untrusted entry, which is the true client.
set_real_ip_from 100.64.0.0/10;
set_real_ip_from 152.233.0.0/17;
set_real_ip_from fd00::/8;
real_ip_header X-Forwarded-For;
real_ip_recursive on;
REALIP
log "nginx real_ip configured for Railway's edge"

# --- 4. nginx: size the worker pool from the cgroup, not the host ------------
# worker_processes auto reads the host's 48 cores, not the container's quota.
NGINX_WORKER_PROCESSES="${NGINX_WORKER_PROCESSES:-2}"
sed -i -E "s/^worker_processes[[:space:]]+.*;/worker_processes ${NGINX_WORKER_PROCESSES};/" deploy/docker/nginx.conf
grep -q "worker_processes ${NGINX_WORKER_PROCESSES};" deploy/docker/nginx.conf || {
    log "FATAL: could not cap nginx worker_processes"; exit 1; }
log "nginx worker_processes=${NGINX_WORKER_PROCESSES}"

# --- 5. celery: cap the prefork pools ----------------------------------------
# celery_long ships with no -c at all, so it forks os.cpu_count() = 48 copies of
# the whole Django app and the container is OOM-killed before it serves. Each
# prefork child is a full copy of the eager-loaded app, so the pool has to be
# sized from memory, not from cores.
CELERY_LONG_CONCURRENCY="${CELERY_LONG_CONCURRENCY:-2}"
CELERY_SHORT_CONCURRENCY="${CELERY_SHORT_CONCURRENCY:-4}"

LONG_CONF=deploy/docker/supervisord/supervisord-celery_long.conf
sed -i -E "s#(celery multi start long1 )#\1-c ${CELERY_LONG_CONCURRENCY} #" "$LONG_CONF"
grep -q -- "-c ${CELERY_LONG_CONCURRENCY} " "$LONG_CONF" || { log "FATAL: celery_long concurrency not set"; exit 1; }

SHORT_CONF=deploy/docker/supervisord/supervisord-celery_short.conf
sed -i -E "s/celery multi start short1 short2 /celery multi start short1 /" "$SHORT_CONF"
sed -i -E "s/-c10/-c ${CELERY_SHORT_CONCURRENCY}/" "$SHORT_CONF"
grep -q -- "-c ${CELERY_SHORT_CONCURRENCY}" "$SHORT_CONF" || { log "FATAL: celery_short concurrency not set"; exit 1; }
log "celery pools: short=${CELERY_SHORT_CONCURRENCY} long=${CELERY_LONG_CONCURRENCY}"

# --- 6. hand over to the image's own launcher --------------------------------
log "starting MediaCMS"
exec deploy/docker/start.real.sh
