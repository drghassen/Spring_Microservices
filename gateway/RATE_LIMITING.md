# Gateway rate limiting

The public `/api/v1/auth/**` route uses Spring Cloud Gateway's
`RequestRateLimiter` with `RedisRateLimiter`. Redis is the shared token store,
so all gateway replicas consume the same bucket for a given client key.

## Trusted client IP chain

```text
Internet
  -> ACA external ingress
  -> client Nginx
  -> X-Client-IP candidate (caller value overwritten)
  -> ACA internal ingress
  -> gateway
  -> RedisRateLimiter
```

An Internet client can supply arbitrary `X-Forwarded-For` and `X-Client-IP`
values. The external ACA ingress appends the address it observes to the right
of `X-Forwarded-For`. Nginx extracts that last token before the request crosses
the internal ACA ingress and always overwrites `X-Client-IP`; it never forwards
`$http_x_client_ip` from the public request. `X-Forwarded-For` is preserved only
for diagnostics and is not used directly as the rate-limit identity.

Nginx only separates the ACA-provided token from the incoming list. The gateway
then accepts it only as one IPv4 or IPv6 literal and canonicalizes it without
DNS resolution. A valid value becomes `ip:<address>`. If `X-Client-IP` is
missing, empty, duplicated, or invalid, the resolver uses the reactive remote
address. In ACA that fallback can identify the internal ingress rather than the
end user. If neither source is usable, the stable fallback is `ip:unknown`.

This PoC relies on two deployment invariants: the external ACA ingress must
continue appending its observed address on the right, and the internal gateway
must only accept trusted callers such as this Nginx proxy. `X-Client-IP` is not
cryptographically authenticated; another caller that can directly reach the
gateway could forge it. A topology change requires reviewing this boundary and
may require network-level caller restrictions, mTLS, or a signed identity
header.

## Configuration

| Environment variable | Local default | ACA POC | Purpose |
| --- | ---: | ---: | --- |
| `REDIS_HOST` | `localhost` | required; injected as `redis` | Shared Redis host |
| `REDIS_PORT` | `6379` | `6379` | Shared Redis port |
| `RATE_LIMIT_AUTH_REPLENISH_RATE` | `5` | `5` | Tokens added per second |
| `RATE_LIMIT_AUTH_BURST_CAPACITY` | `10` | `10` | Maximum tokens in an auth bucket |

The `gateway.yml` development configuration may use `localhost`. The ACA
profile deliberately redeclares `spring.data.redis.host` as `${REDIS_HOST}`
without a fallback. In ACA, `localhost` is the Gateway container itself and can
never represent state shared by two Gateway replicas. The Terraform workload
therefore injects the environment-scoped Container App name `redis` and port
`6379`. The `5/10` values are configurable POC defaults, not the final
anti-bruteforce policy.

## ACA POC architecture

```text
Internet
  -> client ACA ingress and Nginx
  -> gateway (1-2 replicas)
  -> redis:6379 (internal TCP ingress, exactly 1 replica)
```

Redis uses the official `redis:7.4-alpine` image pinned by digest. It has
`minReplicas=1`, `maxReplicas=1`, `0.25` CPU, and `0.5Gi` memory. It is not
reachable through external ACA ingress. TCP startup, readiness, and liveness
probes check port `6379`; no HTTP probe is used for Redis.

Persistence is disabled with `--save "" --appendonly no` and no volume is
mounted. A Redis restart therefore resets rate-limit buckets and temporarily
restores every client's full quota. This is acceptable only for this student
POC because Redis stores no business data.

The POC Redis has no password. Its security boundary is internal-only ACA
ingress within the Container Apps environment. This avoids hardcoding or
inventing fragile password distribution, but it is not an enterprise security
model: another compromised workload in the environment could connect to Redis.
A production design should use Azure Managed Redis or an equivalent highly
available managed service with private networking, TLS, authentication, and
appropriate monitoring. This single-replica Container App is not highly
available.

The official Redis image is intentionally a POC infrastructure exception to
the ACR-managed application release map. It is pinned by version and digest;
the nine application images remain digest-pinned in ACR and keep their existing
release flow.

## Failure and health behavior

Spring Cloud Gateway 4.3.4's native `RedisRateLimiter` is fail-open: if its Lua
call fails because Redis is unavailable, it logs the error and allows the
request with `X-RateLimit-Remaining: -1`. The targeted test suite locks down
this framework behavior so a future dependency upgrade makes any change
visible.

Redis remains visible in the aggregate `/actuator/health` response and through
the dedicated `/actuator/health/redis` group. ACA probes do not use the
aggregate endpoint: liveness checks `/actuator/health/liveness` and readiness
checks `/actuator/health/readiness`. Redis is deliberately not readiness
critical while the native limiter remains fail-open, so a Redis outage does not
remove every Gateway replica from service. The outage remains observable in
health output and in the `RedisRateLimiter` error logs; production alerting must
consume one or both signals.

## Local and Docker

Docker Compose starts the same pinned Redis version on the internal
`microservices` network without publishing port `6379` to the host. The Gateway
uses `REDIS_HOST=redis` and waits for `redis-cli ping` to pass. A Gateway started
directly on the development host keeps the `localhost:6379` default and can use
a disposable host-published Redis:

The unit suite validates filter semantics without requiring an external service.
For a direct-host integration check, start a disposable local container, start
Config Server and the Gateway, then send repeated requests to
`/api/v1/auth/**`:

```shell
docker run --rm -p 6379:6379 redis:7.4-alpine
```

## Dynamic Temporary IP Blocking POC

Rate limiting and IP blocking are deliberately separate decisions. The native
`RedisRateLimiter` protects `/api/v1/auth/**` request by request. A single 429,
or even a very large burst inside one time window, is normal enough that it
never creates a block. Temporary blocking is considered only after the same
client makes three distinct, adjacent windows abusive.

The default POC policy is:

| Setting | Default | Environment variable |
| --- | ---: | --- |
| Mode | `SHADOW` | `IP_BLOCKING_MODE` |
| Fixed window duration | 10 seconds | `IP_BLOCKING_WINDOW_SECONDS` |
| Rate-limiter 429 threshold per window | 3 | `IP_BLOCKING_429_THRESHOLD` |
| Adjacent abusive windows required | 3 | `IP_BLOCKING_WINDOWS_REQUIRED` |
| Temporary block duration | 60 seconds | `IP_BLOCKING_DURATION_SECONDS` |

`abusive-windows-required` is validated to be at least three. ACA and Docker
Compose explicitly set `SHADOW`; changing to `ENFORCE` is a reviewed deployment
decision, not an application default.

### Request and filter order

Only the `/api/v1/auth/**` route installs these ordered route filters:

1. order `-30`, `TemporaryIpBlockFilter`: resolve/caches the client identity
   with the existing `ClientIpKeyResolver`, hash it, and in `ENFORCE` read the
   block TTL;
2. order `-20`, `RateLimitAbuseObserver`: wraps the remaining chain and observes
   its final response;
3. order `0`, `RateLimitOutcomeFilter`: wraps Spring Cloud Gateway 4.3.4's
   native `RequestRateLimiter`, which calls the configured `RedisRateLimiter`;
4. the backend is called only when the native limiter invokes its downstream
   chain; the observer runs its post-processing on the response path.

The outcome wrapper sets `RATE_LIMIT_PASSED` only when the native limiter calls
downstream. If the native filter instead completes a 429 without doing so, it
sets `RATE_LIMIT_REJECTED`. The observer requires that controlled marker as well
as status 429. Therefore an application/backend 429 has `RATE_LIMIT_PASSED` and
is ignored. A block rejection is produced by the outer filter, never enters the
observer, and also carries a separate `TEMP_BLOCK_REJECTED` marker. Status-code
guessing is not used.

Actuator health endpoints are separate handler routes and do not match
`/api/v1/auth/**`; no broad whitelist is necessary and probes never traverse
the blocking filters.

### Windows, consecutive sequence, and Redis state

A fixed window ID is `floor(current UTC epoch milliseconds / configured window
milliseconds)`. Every native rate-limiter 429 atomically increments this key:

```text
abuse:v1:window:<sha256-client-key>:<window-id>
```

The Lua script emits one abusive-window event only when the counter equals the
threshold. Counts greater than the threshold return no event, so 100 rejected
requests in one window still produce one strike. The window key expires after
the time remaining in its fixed window plus one complete window (between 10 and
20 seconds with defaults).

The adjacent-window sequence is a Redis hash:

```text
abuse:v1:sequence:<sha256-client-key>
  last_window = <window-id>
  count       = <adjacent abusive-window count>
```

An abusive window increments `count` only when its ID is exactly
`last_window + 1`; any larger gap starts a new sequence at one. A non-abusive or
missing intervening fixed window therefore breaks the sequence deterministically.
The sequence TTL is `(required windows + 1) * window duration`, 40 seconds by
default, and is refreshed only by an abusive-window event.

On the third adjacent abusive window, `SHADOW` deletes the sequence and emits
`WOULD_BLOCK`. `ENFORCE` atomically deletes the sequence and executes:

```text
SET abuse:v1:block:<sha256-client-key> 1 PX 60000 NX
```

The window increment, one-time threshold transition, adjacent sequence update,
sequence reset, and optional `SET ... PX ... NX` all run in one Redis Lua script.
There is no JVM `GET -> calculate -> SET` race: all Gateway replicas share the
same state, one window produces at most one strike, and at most one block is
created. In-flight rejections see an existing block in the same script and do
not rebuild sequence state.

SHA-256 of the canonical resolver key is used in keys and logs. This is a
stable, non-secret pseudonymous identifier that avoids spreading raw IP
addresses through Redis and logs; no IP or key is used as a metric label.

### Enforcement, response, and lifecycle

Modes have the following behavior:

- `OFF`: no temporary-block lookup and no abuse-state decision; the existing
  native rate limiter remains active.
- `SHADOW`: real window/sequence detection and `WOULD_BLOCK` logging/metrics,
  but no block key and no traffic rejection.
- `ENFORCE`: detection may create the expiring block key, and every Gateway
  replica rejects while its Redis `PTTL` is positive.

An enforced rejection does not call the backend and returns:

```http
HTTP/1.1 429 Too Many Requests
Retry-After: <ceil(remaining Redis PTTL milliseconds / 1000)>
Content-Type: application/json

{"status":429,"error":"Too Many Requests","reason":"TEMPORARILY_BLOCKED"}
```

No IP, Redis key, internal count, or secret is exposed. A positive TTL always
produces at least one second. `PTTL=-2` means absent/expired and traffic is
allowed. `PTTL=-1` would mean an invalid permanent key; it is logged as
`REDIS_BLOCKING_FAILURE` and deliberately fails open rather than enforcing a
permanent block.

Redis TTL is the only unblock mechanism: there is no scheduler, cron, or Java
cleanup job. The sequence is deleted when a block decision is reached, window
state has its own short TTL, and events already in flight are ignored while the
block exists. After expiry, a new client cycle therefore needs three new
adjacent abusive windows. `TEMP_BLOCK_EXPIRED` is not emitted because observing
an absent key cannot reliably distinguish expiry from a key that never existed
without adding durable tracking state.

Any Redis error in lookup or abuse recording logs `REDIS_BLOCKING_FAILURE`,
increments the Redis error counter, and fails open. The request is never denied
merely because Redis is unavailable. This is independent from, and consistent
with, the documented native `RedisRateLimiter` fail-open behavior.

Structured events are `ABUSIVE_WINDOW_DETECTED`, `WOULD_BLOCK`,
`TEMP_BLOCK_CREATED`, `TEMP_BLOCK_REJECTED`, and `REDIS_BLOCKING_FAILURE`.
Metrics have only `mode` and `route_category=auth` tags:

```text
ip_blocking_abusive_windows_total
ip_blocking_would_block_total
ip_blocking_blocks_created_total
ip_blocking_requests_rejected_total
ip_blocking_redis_errors_total
```

### POC limits

This V1 is not complete DDoS protection. It detects one canonical client that
keeps exceeding an authentication rate limit across adjacent windows. It does
not score 401/403 responses, scanning behavior, confidence, users, subnets, or
IOCs; it never creates permanent blocks or modifies Azure networking. A
distributed multi-IP attack requires edge controls such as an appropriate
WAF/CDN and specialized DDoS protection. The single Redis Container App is
itself a non-HA, non-persistent student POC as documented above.
