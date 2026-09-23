# Work package live updates

Browser work package list and detail pages subscribe to ActionCable at `/cable`. A change to status, assignee, or comments is broadcast as a small delta (ids and which of those changed). The page refetches that work package through the existing API and asks the activities tab to pull new journals immediately. Comment text is not on the socket; the activities endpoint still applies visibility, including internal comments.

The activities HTTP poll (about 10 seconds) stays running. If the socket drops, comments still arrive on that poll, and the next page load opens the socket again.

This is separate from MCP seat notifications.

## Server

`config.action_cable.mount_path` is `nil`. `config/routes.rb` mounts `ActionCable.server` at `/cable`, so the route is not dropped when routes reload.

`ApplicationCable::Connection` uses the same login as the HTML app: `session[:user_id]`, then the session cookie (`session_cookie_name`, default `_open_project_session`) via `Sessions::SqlBypass`. Anonymous and inactive users are rejected.

`WorkPackageChannel` accepts one of:

- `work_package_id` — detail page, only if `WorkPackage.visible` for that user
- `project_id` — project list, only if the user has `view_work_packages` on that project
- `visible_projects` — global list, one stream per project that user can view work packages in

Journals for work packages call `WorkPackages::LiveUpdateBroadcaster` after commit. The initial create snapshot is not broadcast unless it includes a comment. A broadcast failure is logged and does not fail the save.

## Redis

`config/cable.yml` already selects the Redis adapter in production (`REDIS_URL`, default `redis://localhost:6379/1`) and the async adapter in development. Tests use the test adapter. This does not install Redis.

## nginx Upgrade

TLS ends at nginx. The browser opens `wss://<public-host>/cable`. nginx forwards the upgrade to Puma (already configured on CloudBSD):

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection $connection_upgrade;
proxy_set_header Host $host;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_read_timeout 86400;
```

Puma then sees HTTP with `Upgrade: websocket` and `X-Forwarded-Proto: https`. `config.force_ssl` treats a request from a trusted local proxy with that header as HTTPS, so it does not redirect the handshake. CSP `connect-src` includes `wss://<request host>` on HTTPS pages and `ws://<request host>` on plain HTTP, in addition to `'self'`.

A plain `GET /cable` without `Upgrade: websocket` is ActionCable's own `404` body `Page not found`. That response means the endpoint is mounted. The handshake that matters is `101 Switching Protocols`.

## Prove on trackdev

Redis is already on loopback `:6379/1`. After this revision is staged:

1. `curl -i https://<host>/cable` returns `404` and body `Page not found`.
2. In the browser network panel, `/cable` switches to `101`.
3. Open a work package list and the same work package in another session. Change status, assignee, or add a comment through the API. The other session's list and detail update within a couple of seconds without a reload.
4. Block `/cable` or drop the socket. The activities tab still updates on the existing poll.
