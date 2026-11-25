# rheem_water_heater

Bash scripts that report on a Rheem EcoNet heat pump water heater through
the Home Assistant REST API.

- `eco-run-history.sh [start-date]` — on/off run history with estimated kWh.
- `eco-status.sh` — one-shot status snapshot.

Both read `HA_TOKEN` from `.env` next to the invoked path, falling back to
`~/.env`; `HA_URL` and `ENV_FILE` override.

Developed on the Mac, run on pibot (Linux) where Home Assistant is at
`http://localhost:8123`. The scripts use GNU `date` and `jq`, so they don't
run as-is on macOS; that is expected.

## Local checks

No tests. Before deploying, run `bash -n` on each `*.sh`.

## Pi deploy

- Checkout: `~/projects/rheem_water_heater` on pibot, origin
  `https://github.com/mikeoc61/rheem_water_heater.git`.
- Post-pull steps: none. `~/bin/eco-run-history.sh` and
  `~/bin/eco-status.sh` are symlinks into the checkout, so the pull
  updates them. A new script that should be on PATH needs a matching
  symlink in `~/bin`.
- Services, timers, cron: none use these scripts; nothing to restart.
- Env: `~/.env` (symlink to `~/.openclaw/openclaw.env`) and `~/bin/.env`
  both hold `HA_TOKEN`. Invoked via `~/bin`, both scripts read
  `~/bin/.env`; from the checkout they fall back to `~/.env`.
- Pi checks (read-only Home Assistant GETs, safe to run every deploy), from
  the checkout; all must exit 0:
  - `./eco-status.sh`
  - `NO_COLOR=1 ./eco-run-history.sh "$(date +%Y-%m-%d)"`
  - `~/bin/eco-status.sh` to confirm the symlink still resolves.
