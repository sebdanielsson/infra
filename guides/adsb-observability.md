# ADS-B observability

Dashboards and a live map for the Uppsala ADS-B receiver, without touching the
Flightradar24 feed.

## Where to look

| What | URL | Notes |
| ---- | --- | ----- |
| Sky Watch dashboard | <https://grafana.risk-bee.ts.net/d/adsb-skywatch> | What flew over, when and where. Grafana's home page. |
| Receiver health dashboard | <https://grafana.risk-bee.ts.net/d/adsb-receiver> | Message rates, range, signal, Pi health. |
| Live map (tar1090) | <https://tar1090.risk-bee.ts.net> | Trails, heatmap (`/?heatmap`), replay, range outline. |
| Decoder graphs (graphs1090) | <https://tar1090.risk-bee.ts.net/graphs1090/> | The classic RRD view. |
| FR24 feeder status | <https://fr24.risk-bee.ts.net> | Was the old `:8754` page; still on that port too. |
| Prometheus | <https://prometheus.risk-bee.ts.net> | Raw metrics and target health. |

All of these are tailnet-only — DockTail publishes them as Tailscale services,
so they are HTTPS with real certificates and never exposed to the internet.

## Credentials

Grafana's local admin login is `admin`, and the password lives sops-encrypted
in `docker/prometheus-grafana/.env.sops`:

```sh
SOPS_AGE_KEY_FILE=$PWD/arcane.agekey \
  sops --input-type dotenv --output-type dotenv \
  --decrypt --extract '["GRAFANA_ADMIN_PASSWORD"]' docker/prometheus-grafana/.env.sops
```

Worth copying into the password manager next to the age key. Rotating it is
`sops edit` on that file followed by a redeploy — Grafana applies
`GF_SECURITY_ADMIN_PASSWORD` to the existing admin user on every start.

The same file holds the antenna coordinates, which are also in
`ansible/.env.flightradar.sops` for the receiver side. They are encrypted
rather than committed in the open because they are the home address in another
coordinate system.

## How it fits together

```text
                     flightradar (Raspberry Pi)
  RTL-SDR ──► dump1090-fa ──┬──► fr24feed ──────────────► Flightradar24
              (owns the     │    (Beast, port 30005)
               dongle)      │
                            └──► ultrafeeder ──┬──► tar1090 + graphs1090  :8504
                                 (readsb,      │
                                  net-only)    └──► readsb /metrics       :9274
                                 node-exporter ────────────────────────►  :9100

                     hogsmeade
  prometheus ◄── scrapes :9274 and :9100 over the tailnet
  adsb-logger ◄── polls :8504/data/aircraft.json ──► SQLite flight log
  grafana ◄── Prometheus + the SQLite flight log
```

`dump1090-fa` keeps ownership of the SDR, so nothing about the Flightradar24
feed changed structurally. `readsb` runs `--net-only`, consuming the same Beast
stream fr24feed does. `TAR1090_ENABLE_AC_DB=true` makes readsb annotate
`aircraft.json` with registration, ICAO type, a description and the military
flag — which is what makes the flight log interesting.

### Two data stores, on purpose

Prometheus answers *how is the receiver doing* — rates, gauges, ranges over
time. It is the wrong tool for *which* aircraft flew over: one time series per
airframe would blow up the cardinality.

So `adsb-logger` (`docker/prometheus-grafana/adsb-logger/logger.py`) polls
`aircraft.json` every 5 s and keeps a **sighting** table in SQLite — one row per
continuous stretch of contact with one aircraft, with the callsign, airline,
registration, type, country of registration, altitude range, closest and
furthest distance, and peak signal. Alongside it a **position** table keeps one
track point per aircraft per 30 s, which is what the coverage heatmap and the
range-by-direction chart are built from.

It is deliberately stdlib-only, so the container is a stock `python:*-alpine`
with no build step and no `pip install` at runtime. Airline names come from
OpenFlights, downloaded once a month into an `airline` table; ICAO 24-bit
address → country uses tar1090's own allocation table so the attribution
matches the map.

Retention defaults: positions 30 days (~3.5 M rows, a few hundred MB),
sightings 2 years. Both are environment variables on the `adsb-logger` service.

## Deployment

The two halves are managed differently, matching the rest of this repo:

- **flightradar** — Ansible. `ansible/tasks/adsb-stack.yml` copies
  `docker/adsb/compose.yaml` and `docker/docktail/compose.yaml` to
  `/docker/<stack>/`, writes each `.env` from the playbook's sops-decrypted
  environment, and runs `docker compose up`. There is no age key on this host
  and no Arcane.
- **hogsmeade** — Arcane GitOps, like every other stack there. See
  [the migration guide](./arcane-gitops-migration.md); `prometheus-grafana` is
  in [`arcane-gitops-import.json`](./arcane-gitops-import.json) and needs the
  standard sops pre-deploy hook, because it carries secrets.

Grafana's datasources and both dashboards are provisioned from git
(`grafana/provisioning/`, `grafana/dashboards/`) with `allowUiUpdates: false`.
Edit a dashboard in the UI to experiment; commit the JSON to keep it.

### One-time Arcane setup

`prometheus-grafana` was deployed by hand into `/docker/prometheus-grafana`
first so it would come up immediately. To hand it over to GitOps: Projects →
Git Sync → import the entry, then add the pre-deploy hook —

| Setting      | Value                                             |
| ------------ | ------------------------------------------------- |
| Script path  | `pre-deploy.sh`                                   |
| Runner image | `ghcr.io/getsops/sops:v3.13.2-alpine`             |
| Network      | `none`                                            |
| Environment  | `SOPS_AGE_KEY_FILE=/run/secrets/age.key`          |
| Extra mounts | `/docker/secrets/age.key:/run/secrets/age.key:ro` |

The first sync recreates the containers under the same project name; the named
volumes (`prometheus_data`, `grafana_data`, `adsb_flightlog`) persist.

## Notes and caveats

- **No host ports on hogsmeade.** 3000, 9090, 9091 and 9099 are all taken
  there, and DockTail proxies straight to the container IP, so neither
  Prometheus nor Grafana publishes a port. To poke at them from a shell:
  `docker run --rm --network prometheus-grafana curlimages/curl -s http://grafana:3000/api/health`.
- **`fr24-proxy`** exists only because DockTail prunes any tailnet service it
  does not manage, and fr24feed runs on the host rather than in a container.
  The socat forwarder gives DockTail something to attach `svc:fr24` to.
- **FR24 MLAT.** fr24feed now reads Beast on 30005 instead of AVR on 30002,
  which cleared the old `rx-incompatible` error. It now reports
  `mlat-ok: NOT-PERMITTED` / `mlat-disabled`, which is decided by FR24's
  server: set the receiver's position under
  [Data sharing](https://www.flightradar24.com/account/data-sharing) on the
  FR24 account and MLAT should be granted on the next reconnect.
- **`readsb_distance_max` is cumulative** since readsb last started — it only
  ever steps up. Range within a time window comes from the flight log on Sky
  Watch, not from Prometheus.
- **Antenna altitude** is set to 30 m in `ansible/.env.flightradar.sops`
  (`ADSB_ALT_M`). It only affects the theoretical-horizon overlay; adjust if
  the real figure is known.
- **globe_history** (tar1090 replay and heatmap) is capped at 14 days via
  `MAX_GLOBE_HISTORY` to keep SD-card writes down. The long history lives in
  the SQLite flight log on hogsmeade instead.
- **Image tags.** `sdr-enthusiasts` publishes no semver tags, only
  `latest-build-<n>`; `.github/renovate.json` has a regex versioning rule so
  Renovate can still bump it.
