# mediacms-railway

[MediaCMS](https://github.com/mediacms-io/mediacms) packaged for
[Railway](https://railway.com). One `FROM mediacms/mediacms:latest` layer plus a
launcher — upstream's image already runs nginx, gunicorn, both celery pools and
celery beat under supervisord, so nothing is rebuilt.

## What this layer adds

| Change | Why |
|---|---|
| `SECURE_PROXY_SSL_HEADER` + `CSRF_TRUSTED_ORIGINS` appended to `deploy/docker/local_settings.py` | Railway terminates TLS at the edge. Without these Django sees the request as plain HTTP, builds the expected CSRF origin as `http://<host>`, and answers every POST from the https page — login, upload, comment — with 403. MediaCMS exposes neither as an environment variable. |
| nginx moved from `:80` to `$PORT` | gunicorn is bound to `127.0.0.1:9000`, so nginx is the only listener Railway's health check and edge can reach. |
| `worker_processes` capped | `auto` reads the host's 48 cores, not the container's CPU quota. |
| `celery_long` given `-c` | Upstream passes no concurrency flag, so celery forks `os.cpu_count()` copies of the whole Django app and the container is OOM-killed while booting. |
| `media_files` defaults seeded at boot | The volume mounts over the directory where the image ships its default avatar, banner and audio poster. |
| `ClientIPMiddleware` | Railway's edge and the image's own nginx both sit in front of Django, so `REMOTE_ADDR` is otherwise always `127.0.0.1` and every anonymous like, report and watch is attributed to one address. |

Everything is driven by environment variables; no file in this repo needs editing
to deploy it.

## Required variables

| Variable | Notes |
|---|---|
| `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_NAME` | reference a Railway Postgres service |
| `REDIS_LOCATION` | `redis://…/1` — celery broker and Django cache |
| `SECRET_KEY` | must be stable; sessions and password-reset tokens are signed with it |
| `FRONTEND_HOST` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` |
| `PORT` | the port nginx is moved onto |
| `ADMIN_USER`, `ADMIN_EMAIL`, `ADMIN_PASSWORD` | the first admin, created only while the user table is empty |

## Optional variables

`PORTAL_NAME`, `PORTAL_DESCRIPTION`, `PORTAL_WORKFLOW` (`public`/`unlisted`/`private`),
`DEFAULT_THEME`, `TIME_ZONE`, `CAN_ADD_MEDIA`, `CAN_COMMENT`,
`USERS_CAN_SELF_REGISTER`, `USERS_NEEDS_TO_BE_APPROVED`, `GLOBAL_LOGIN_REQUIRED`,
`ALLOWED_DOMAINS_FOR_USER_REGISTRATION`, `RESTRICTED_DOMAINS_FOR_USER_REGISTRATION`,
`GENERATE_SITEMAP`, `EXTRA_CSRF_TRUSTED_ORIGINS`, `SECURE_HSTS_SECONDS`, `LOG_LEVEL`,
`EMAIL_HOST`, `EMAIL_PORT`, `EMAIL_HOST_USER`, `EMAIL_HOST_PASSWORD`, `EMAIL_USE_TLS`,
`DEFAULT_FROM_EMAIL`, `ADMIN_EMAIL_LIST`,
`NGINX_WORKER_PROCESSES`, `CELERY_SHORT_CONCURRENCY`, `CELERY_LONG_CONCURRENCY`,
`USER_CAN_TRANSCRIBE_VIDEO`.

`USER_CAN_TRANSCRIBE_VIDEO` is off by default: the `whisper` CLI it shells out to
only ships in `mediacms/mediacms:full`. Change the `FROM` line to that image to
turn it on.

## Volume

Mount one volume at `/home/mediacms.io/mediacms/media_files`. Uploads, encoded
renditions and HLS segments all live there, and the celery workers write to the
same directory as the web tier — which is why every role runs in this one
container rather than as separate Railway services.

Licensed AGPL-3.0, same as MediaCMS.
