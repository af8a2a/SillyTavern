# SillyTavern Headless API

This project exposes a first-pass headless API under `/api/headless/v1` for
custom web, mobile, desktop, or WebView clients.

The API is mounted behind the same authentication and CSRF middleware as the
existing private SillyTavern APIs. It does not introduce a separate config file,
token store, or multi-user session model.

## Client App

An installable PWA client is served from:

```text
/headless/
```

The app uses the headless API, stores only a small library cache in
`localStorage`, and keeps SillyTavern data on the server.

## Authentication And CSRF

Clients should call all endpoints with cookies:

```js
await fetch('/api/headless/v1/library', { credentials: 'include' });
```

For mutating requests, get a CSRF token first:

```js
const { token } = await fetch('/csrf-token', { credentials: 'include' }).then(r => r.json());

await fetch('/api/headless/v1/characters/example.png', {
    method: 'PATCH',
    credentials: 'include',
    headers: {
        'content-type': 'application/json',
        'x-csrf-token': token,
    },
    body: JSON.stringify({
        name: 'Example',
        data: { name: 'Example' },
    }),
});
```

If user accounts are enabled and the client is not logged in, the API returns
`403`.

## Reverse Proxy

Existing SillyTavern configuration already has the building blocks needed for a
reverse-proxied deployment:

- `listen`, `listenAddress`, and `port` control local bind behavior.
- `hostWhitelist.hosts` allows public proxy hostnames.
- `forwardedHeaders` and `sso.trustedProxies` support reverse-proxy client IP
  and SSO flows.
- `requestProxy` is only for outgoing HTTP/HTTPS requests from SillyTavern. It
  is not an incoming reverse-proxy target.
- `Remote-Link.cmd` starts a temporary Cloudflare tunnel, but it does not store
  a persistent public app URL.

Headless public app metadata can be kept in `config.yaml`:

```yaml
headless:
  remoteApp:
    enabled: true
    publicUrl: "https://st.example.com"
    proxyTarget: "http://127.0.0.1:8000"
    appPath: "/headless/"
    apiPath: "/api/headless/v1"
    assetPaths:
      - "/thumbnail"
      - "/characters"
      - "/backgrounds"
      - "/csrf-token"
      - "/login"
      - "/api/users"
    healthPath: "/api/headless/v1/bootstrap"
```

This metadata is returned by `/api/headless/v1/bootstrap` and is printed by the
`run_server` script. It does not start nginx, Caddy, Cloudflare Tunnel, or any
other proxy process by itself.

For same-origin public deployment, proxy the public app and API paths to the
local SillyTavern server. A minimal nginx shape:

```nginx
location /headless/ {
    proxy_pass http://127.0.0.1:8000/headless/;
}

location /api/headless/ {
    proxy_pass http://127.0.0.1:8000/api/headless/;
}

location /csrf-token {
    proxy_pass http://127.0.0.1:8000/csrf-token;
}

location /thumbnail {
    proxy_pass http://127.0.0.1:8000/thumbnail;
}

location /characters/ {
    proxy_pass http://127.0.0.1:8000/characters/;
}

location /backgrounds/ {
    proxy_pass http://127.0.0.1:8000/backgrounds/;
}

location /login {
    proxy_pass http://127.0.0.1:8000/login;
}

location /api/users/ {
    proxy_pass http://127.0.0.1:8000/api/users/;
}
```

Use HTTPS and keep SillyTavern's normal authentication controls enabled when
exposing the proxy outside a trusted network.

## Running

Use the normal server entry point or the headless-aware wrapper:

```bash
npm run run_server
```

The wrapper uses the same config initialization and command-line arguments as
`server.js`, then logs `headless.remoteApp` before starting the server. Arguments
are passed through, for example:

```bash
npm run run_server -- --port 8010 --listen
```

## Endpoints

### Bootstrap

```http
GET /api/headless/v1/bootstrap
```

Returns the current user, route roots, media URL templates, and advertised
capabilities.

### Library

```http
GET /api/headless/v1/library
```

Returns shallow characters, groups, worlds, and backgrounds in one request.

### Characters

```http
GET /api/headless/v1/characters
GET /api/headless/v1/characters?full=true
GET /api/headless/v1/characters/:avatar
PATCH /api/headless/v1/characters/:avatar
```

`PATCH` accepts a direct merge payload. It also accepts `{ "patch": { ... } }`
if a wrapper is preferred. The server validates the resulting card with the
existing TavernCard validator.

### Character Chats

```http
GET /api/headless/v1/characters/:avatar/chats
POST /api/headless/v1/characters/:avatar/chats
GET /api/headless/v1/characters/:avatar/chats/:chatId
PUT /api/headless/v1/characters/:avatar/chats/:chatId
POST /api/headless/v1/characters/:avatar/chats/:chatId/messages
DELETE /api/headless/v1/characters/:avatar/chats/:chatId
```

Chat payloads can be an array, `{ "messages": [...] }`, or `{ "chat": [...] }`.
If a chat metadata header is missing, the server creates one.

### Groups

```http
GET /api/headless/v1/groups
GET /api/headless/v1/groups/:groupId
GET /api/headless/v1/groups/:groupId/chats/:chatId
PUT /api/headless/v1/groups/:groupId/chats/:chatId
```

Group chat writes use the same JSONL format and backup path as existing group
chat endpoints.

### Worlds

```http
GET /api/headless/v1/worlds
GET /api/headless/v1/worlds/:name
PUT /api/headless/v1/worlds/:name
DELETE /api/headless/v1/worlds/:name
```

World writes require an object with an `entries` property.

### Backgrounds

```http
GET /api/headless/v1/backgrounds
```

Returns background filenames and thumbnail URLs.
