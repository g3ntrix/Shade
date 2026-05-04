# Shade VPS exit worker

Node HTTP server used as a **Shade exit relay** (same wire format as val.town: JSON body with `k`, `u`, `m`, `h`, `b`).

- Set **`EXIT_NODE_PSK`** in the environment to a strong secret (≥ 8 characters). Use the same value as the tunnel PSK in Shade → Settings → Exit node.
- Default listen port **8081** (override with `PORT`). If something else already uses 8081, set e.g. `PORT=18081` and open that port in your cloud firewall.
- PM2: copy `ecosystem.config.example.cjs` → `ecosystem.config.cjs`, edit secrets, then run **`pm2 start ecosystem.config.cjs`** (a bare `pm2 start` looks for `ecosystem.config.js` only).
- If the JSON body includes a **`k`** field, the request is handled as Shade exit traffic (PSK required). If **`k`** is absent, the server behaves like the legacy mhr-vps-worker relay (no PSK) — avoid exposing that on the public internet without other protections.

Installer: run `bash /root/shade-exit-relay/install.sh` after extracting the bundle on your VPS. It auto-selects a free port, generates PSK, starts PM2, and prints Relay URL + PSK.
