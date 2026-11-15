# anacrolix

A small headless BitTorrent daemon on [anacrolix/torrent](https://github.com/anacrolix/torrent), run next to Transmission to try the library on hogsmeade. It is a service in the `transmission-wireguard` stack, so it shares the WireGuard tunnel and the VPN credentials.

## How it runs

- Network: `network_mode: service:wireguard`. It asks the VPN gateway (10.2.0.1) for a NAT-PMP mapping, TCP and UDP, renews it before it expires, and listens for peers on the forwarded port. If the gateway hands out a different port, the process exits and Docker restarts it on the new one.
- Only one client can run at a time: Transmission and anacrolix get the same forwarded port. Switch with `deploy.replicas` in `../compose.yaml` (one service at 1, the other at 0).
- Build: the stock `golang` image compiles this module at container start; `anacrolix_cache` keeps the module and build caches. `pre-deploy.sh` writes a hash of this directory to `.env` so a code change recreates the container.
- Storage: payloads in `/chungus/media/downloads/anacrolix/files` (same pool as Transmission); piece completion and saved `.torrent`/`.magnet` files in the `anacrolix_data` volume on the SSD. `DISABLE_MMAP=true` switches the file storage from mmap to plain reads and writes.

## Using it

The status page is at `https://anacrolix.risk-bee.ts.net` (DockTail), with Transmission's username and password. To add a torrent, POST a magnet URI or a `.torrent` file to `/add`, or drop a `.torrent` or `.magnet` file into `/chungus/media/downloads/anacrolix/watch`:

```sh
curl -u "$USER:$PASS" --data-binary 'magnet:?xt=urn:btih:...' https://anacrolix.risk-bee.ts.net/add
curl -u "$USER:$PASS" --data-binary @file.torrent https://anacrolix.risk-bee.ts.net/add
```

| Path       | What                                                              |
| ---------- | ----------------------------------------------------------------- |
| `/`        | Torrents with progress, rates and peers                           |
| `/status`  | anacrolix's own status dump                                       |
| `/add`     | POST a magnet URI or `.torrent` file                              |
| `/remove`  | POST an infohash; `?files=delete` also deletes its data           |
| `/metrics` | Prometheus metrics, including Go runtime CPU and memory (no auth) |
| `/healthz` | Health check (no auth)                                            |
