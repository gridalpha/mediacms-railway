"""Recover the real client address behind Railway's edge.

MediaCMS records ``REMOTE_ADDR`` against anonymous likes, reports and watch
events.  Two proxies sit in front of Django here — Railway's edge and the
image's own nginx — so ``REMOTE_ADDR`` is always ``127.0.0.1`` and every
anonymous visitor is attributed to the same address.

Railway's edge overwrites a client-supplied ``X-Forwarded-For``, so its
*leftmost* entry is the true client and is not spoofable.  The in-container
nginx appends to the header rather than replacing it, which leaves the leftmost
entry intact.
"""


class ClientIPMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        forwarded = request.META.get("HTTP_X_FORWARDED_FOR", "")
        if forwarded:
            client = forwarded.split(",")[0].strip()
            if client:
                request.META["REMOTE_ADDR"] = client
        return self.get_response(request)
