import os


def zap_started(zap, target):
    token = os.environ.get("DAST_JWT_TOKEN", "").strip()
    if not token:
        return

    zap.replacer.add_rule(
        "DAST JWT Authorization header",
        "true",
        "REQ_HEADER",
        "false",
        "Authorization",
        "Bearer " + token,
    )
