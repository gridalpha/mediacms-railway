
# ---------------------------------------------------------------------------
# Railway overrides, appended to MediaCMS' own deploy/docker/local_settings.py
# by the Dockerfile. Everything below is read from the environment so the whole
# deployment is configurable without editing a file.
# ---------------------------------------------------------------------------
import os as _os


def _rw_bool(name, default):
    return _os.getenv(name, "true" if default else "false").strip().lower() in ("1", "true", "yes", "on")


def _rw_list(name, default=""):
    return [item.strip() for item in _os.getenv(name, default).split(",") if item.strip()]


# --- public URL -------------------------------------------------------------
# Railway's RAILWAY_PUBLIC_DOMAIN carries the host only, so accept both forms.
_rw_host = _os.getenv("FRONTEND_HOST", "http://localhost").strip().rstrip("/")
if "://" not in _rw_host:
    _rw_host = "https://" + _rw_host
FRONTEND_HOST = _rw_host

# --- running behind Railway's TLS edge --------------------------------------
# The edge terminates TLS and the in-container nginx forwards the scheme, so
# Django has to be told to believe the header. Without this, request.is_secure()
# is False, Django builds the expected CSRF origin as http://<host>, and every
# POST from the https page (login, upload, comment) is rejected 403.
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
CSRF_TRUSTED_ORIGINS = list(
    dict.fromkeys(
        [FRONTEND_HOST, FRONTEND_HOST.replace("http://", "https://")]
        + _rw_list("EXTRA_CSRF_TRUSTED_ORIGINS")
    )
)
SESSION_COOKIE_SECURE = _rw_bool("SESSION_COOKIE_SECURE", True)
CSRF_COOKIE_SECURE = _rw_bool("CSRF_COOKIE_SECURE", True)
# Railway's edge already 301s http->https. Doing it in Django as well would
# starve the health check, which speaks plain HTTP and sends no X-Forwarded-Proto.
SECURE_SSL_REDIRECT = False
SECURE_HSTS_SECONDS = int(_os.getenv("SECURE_HSTS_SECONDS", "31536000"))
SECURE_HSTS_INCLUDE_SUBDOMAINS = False
SECURE_HSTS_PRELOAD = False

# --- portal identity and behaviour ------------------------------------------
PORTAL_NAME = _os.getenv("PORTAL_NAME", "MediaCMS")
PORTAL_DESCRIPTION = _os.getenv("PORTAL_DESCRIPTION", "")
PORTAL_WORKFLOW = _os.getenv("PORTAL_WORKFLOW", "public")
DEFAULT_THEME = _os.getenv("DEFAULT_THEME", "light")
TIME_ZONE = _os.getenv("TIME_ZONE", "UTC")
CAN_ADD_MEDIA = _os.getenv("CAN_ADD_MEDIA", "all")
CAN_COMMENT = _os.getenv("CAN_COMMENT", "all")
USERS_CAN_SELF_REGISTER = _rw_bool("USERS_CAN_SELF_REGISTER", True)
REGISTER_ALLOWED = USERS_CAN_SELF_REGISTER
USERS_NEEDS_TO_BE_APPROVED = _rw_bool("USERS_NEEDS_TO_BE_APPROVED", False)
GLOBAL_LOGIN_REQUIRED = _rw_bool("GLOBAL_LOGIN_REQUIRED", False)
ALLOWED_DOMAINS_FOR_USER_REGISTRATION = _rw_list("ALLOWED_DOMAINS_FOR_USER_REGISTRATION")
RESTRICTED_DOMAINS_FOR_USER_REGISTRATION = _rw_list("RESTRICTED_DOMAINS_FOR_USER_REGISTRATION")
GENERATE_SITEMAP = _rw_bool("GENERATE_SITEMAP", False)

# The `whisper` CLI only ships in the mediacms/mediacms:full image, so the
# transcribe buttons would queue a task that can never run on the base image.
USER_CAN_TRANSCRIBE_VIDEO = _rw_bool("USER_CAN_TRANSCRIBE_VIDEO", False)

# --- email ------------------------------------------------------------------
# Defaults point at the bundled Mailpit service. A dangling cross-service
# reference renders as an empty string rather than staying unset, so repair the
# value on its shape instead of relying on os.getenv's default.
EMAIL_HOST = _os.getenv("EMAIL_HOST", "").strip() or "mailpit.railway.internal"
EMAIL_PORT = int(_os.getenv("EMAIL_PORT", "1025") or "1025")
EMAIL_HOST_USER = _os.getenv("EMAIL_HOST_USER", "")
EMAIL_HOST_PASSWORD = _os.getenv("EMAIL_HOST_PASSWORD", "")
EMAIL_USE_TLS = _rw_bool("EMAIL_USE_TLS", False)
EMAIL_USE_SSL = _rw_bool("EMAIL_USE_SSL", False)
DEFAULT_FROM_EMAIL = _os.getenv("DEFAULT_FROM_EMAIL", "mediacms@example.com")
SERVER_EMAIL = DEFAULT_FROM_EMAIL
ADMIN_EMAIL_LIST = _rw_list("ADMIN_EMAIL_LIST") or _rw_list("ADMIN_EMAIL") or [DEFAULT_FROM_EMAIL]

# --- logging ----------------------------------------------------------------
# Django logs unhandled 500s nowhere at all with DEBUG=False, because the stock
# console handler sits behind require_debug_true.
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {"plain": {"format": "%(asctime)s %(levelname)s %(name)s %(message)s"}},
    "handlers": {"console": {"class": "logging.StreamHandler", "formatter": "plain"}},
    "root": {"handlers": ["console"], "level": _os.getenv("LOG_LEVEL", "INFO")},
    "loggers": {
        "django.request": {"handlers": ["console"], "level": "ERROR", "propagate": False},
        "django.db.backends": {"handlers": ["console"], "level": "WARNING", "propagate": False},
    },
}
