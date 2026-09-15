# MediaCMS on Railway.
#
# Upstream's image is already a complete single-container deployment — nginx,
# gunicorn, the two celery pools and celery beat under supervisord — so this
# adds only what Railway needs and changes nothing else:
#
#   * Django has to trust X-Forwarded-Proto and carry CSRF_TRUSTED_ORIGINS, or
#     every POST from the https page is rejected 403. MediaCMS exposes neither
#     as an environment variable; upstream's own answer is "edit
#     local_settings.py", so that file is what this appends to.
#   * nginx hardcodes :80 and gunicorn is bound to 127.0.0.1:9000, so the
#     launcher moves nginx onto Railway's $PORT.
#   * celery_long ships with no concurrency flag and forks one copy of the whole
#     Django app per *host* core (48 here) — an OOM kill before the first boot
#     completes.
#   * upstream's .dockerignore excludes media_files/**, so the default user
#     avatar and channel banner every account falls back to are missing from the
#     published image entirely — their compose supplies them by bind-mounting
#     the host checkout. They are vendored here and seeded onto the volume.
FROM mediacms/mediacms:latest

USER root
WORKDIR /home/mediacms.io/mediacms

COPY railway_client_ip.py cms/railway_client_ip.py
COPY railway_local_settings.py /opt/railway/railway_local_settings.py
COPY start.sh /opt/railway/start.sh
COPY media_seed /opt/railway/media_seed

RUN set -eux; \
    # users.User.logo defaults to userlogos/user.jpg and the channel banner to
    # userlogos/banner.jpg, so without these every avatar is a broken image
    test -s /opt/railway/media_seed/userlogos/user.jpg; \
    test -s /opt/railway/media_seed/userlogos/banner.jpg; \
    test -s /opt/railway/media_seed/userlogos/poster_audio.jpg; \
    # recover the real client IP: two proxies sit in front of Django, so
    # REMOTE_ADDR is otherwise always 127.0.0.1
    sed -i 's|^MIDDLEWARE = \[|MIDDLEWARE = [\n    "cms.railway_client_ip.ClientIPMiddleware",|' cms/settings.py; \
    grep -q 'cms.railway_client_ip.ClientIPMiddleware' cms/settings.py; \
    # append rather than replace, so this survives an upstream change to the file
    cat /opt/railway/railway_local_settings.py >> deploy/docker/local_settings.py; \
    grep -q 'CSRF_TRUSTED_ORIGINS' deploy/docker/local_settings.py; \
    python -c "import ast; ast.parse(open('cms/settings.py').read())"; \
    python -c "import ast; ast.parse(open('deploy/docker/local_settings.py').read())"; \
    # shim the launcher the image's CMD names; declaring an ENTRYPOINT here
    # would empty the inherited CMD and skip upstream's own chown/secret setup
    mv deploy/docker/start.sh deploy/docker/start.real.sh; \
    cp /opt/railway/start.sh deploy/docker/start.sh; \
    chmod +x deploy/docker/start.sh deploy/docker/start.real.sh; \
    bash -n deploy/docker/start.sh; \
    command -v nginx; command -v ffmpeg; command -v supervisord
