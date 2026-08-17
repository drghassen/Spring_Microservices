import os


def zap_started(zap, target):
    token = os.environ.get("DAST_JWT_TOKEN", "").strip()
    if not token:
        return

    gateway_api_url_regex = os.environ.get(
        "DAST_AUTH_URL_REGEX",
        r"^http://gateway:8222/(USER-SERVICE|GAMES-SERVICE|ORDER-SERVICE|PAYMENT-SERVICE|LIBRARY-SERVICE)(/|$)",
    )

    zap.replacer.add_rule(
        "DAST JWT Authorization header",
        "true",
        "REQ_HEADER",
        "false",
        "Authorization",
        "Bearer " + token,
        url=gateway_api_url_regex,
    )
