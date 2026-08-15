# Companion Service API

Brockbuster's community features (Server Health, Friends, People) are powered by a small web
service that lives **next to** your Jellyfin server, not inside it. This repo contains only the
client; this document describes the HTTP contract the client expects so you can implement a
compatible backend for your own community.

To enable these features in the app, set `AppConfig.serviceBaseURL` to your service's origin
(e.g. `https://media.example.com`). The client calls `<serviceBaseURL>/api/...`.

The Swift models in [`Brockbuster/BrockbusterAPI.swift`](../Brockbuster/BrockbusterAPI.swift) are
the authoritative reference; this document is derived from them.

## Authentication

Every request is a `GET` with these headers:

```
Authorization: Bearer <jellyfin access token>
X-JF-UserId: <jellyfin user id>
Accept: application/json
User-Agent: BrockbusterApple/1.0
```

The client sends the user's **Jellyfin** token. Your service must validate it server-side against
your Jellyfin instance (e.g. by calling a Jellyfin endpoint with the token and checking that the
authenticated user matches `X-JF-UserId`). Never trust the headers without validating them.

## Response conventions

The client accepts either shape for success:

- **Flat**: payload fields at the top level alongside `"ok": true`
- **Envelope**: `{ "ok": true, "data": { ...payload... } }`

Errors should use a non-2xx status; the client will surface `error` if the body is
`{ "ok": false, "error": "message" }`. All payload fields are optional in the client models —
omit what you don't have. Field names are `snake_case`.

## Endpoints

### `GET /api/health?v=2`

Powers the Server Health tab.

```jsonc
{
  "ok": true,
  "version": 2,
  "generated_at": "2026-01-05T20:13:39Z",   // ISO 8601
  "status": {
    "server_online": true,
    "severity": "ok",                        // e.g. "ok" | "warning" | "critical"
    "badges": [ { "type": "critical", "label": "5 drive(s) critical" } ],
    "banner": null                           // optional banner message
  },
  "hardware": {
    "cpu":    { "name": "…", "util_percent": 12.5 },
    "gpu":    { "name": "…", "util_percent": 4.0, "vram_used_mb": 512, "vram_total_mb": 8192 },
    "memory": { "used_gb": 12.1, "total_gb": 32.0 }
  },
  "network": { "uptime_seconds": 123456 },
  "storage": {
    "thresholds": { "warning_free_percent": 15, "critical_free_percent": 5 },
    "drives": [
      {
        "mount": "D:",
        "label": "Media Drive",
        "role": "media",                     // e.g. "os" | "media"
        "severity": "critical",              // drives the WARNING/CRITICAL pill
        "used_bytes": 6323000000000,
        "free_bytes": 119700000000,
        "total_bytes": 6442700000000,
        "free_percent": 1.9
      }
    ]
  },
  "checks": { "jellyfin_public_info_ok": true },
  "caller": { "userId": "…", "name": "…" }   // echo of the authenticated user
}
```

### `GET /api/friends`

Powers the Friends screen (accepted + pending lists).

```jsonc
{
  "ok": true,
  "version": 1,
  "me": { "id": 1, "display_name": "Brock", "is_public": true },
  "friends": [
    {
      "friendship_id": 10,
      "status": "friends",
      "created_at": "2026-01-01T00:00:00Z",
      "user": {
        "id": 2,
        "display_name": "Brooke",
        "avatar_url": "https://…",
        "is_public": true,
        "jellyfin_user_id": "…"
      }
    }
  ],
  "pending": [ /* same shape as friends */ ]
}
```

### `GET /api/people?limit=24&offset=0&query=…`

Powers the People directory (public profiles, with search). `query` is omitted when empty;
`limit` is clamped to 1–100 by the client.

```jsonc
{
  "ok": true,
  "version": 1,
  "query": null,
  "limit": 24,
  "offset": 0,
  "results": [
    {
      "id": 2,
      "display_name": "Brooke",
      "avatar_url": "https://…",
      "is_public": true,
      "relationship": "none"                 // "friends" | "pending" | "none"
    }
  ]
}
```

## Privacy notes

If you build a backend, a few defaults worth copying: make profiles opt-in (`is_public`), never
expose attendance/watch data through `/api/people`, and treat the health endpoint as
authenticated-users-only since drive layouts and hardware details are more than you want public.
