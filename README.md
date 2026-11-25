# rheem_water_heater

Command-line reports for a Rheem EcoNet heat pump water heater, using the
[Home Assistant](https://www.home-assistant.io/) REST API and the EcoNet
integration's entities.

| Script | What it shows |
|---|---|
| `eco-status.sh` | A snapshot of the current mode, running state, available hot water, energy used today, health and alerts |
| `eco-run-history.sh [start-date]` | Every heating run since the start date: when it started, how long it ran, idle time before it, the mode, and estimated kWh |

## Requirements

- Linux with GNU coreutils (`date -d`); the scripts don't run as-is on macOS
- `bash`, `curl` and `jq`
- Home Assistant with the Rheem EcoNet integration, plus a
  [long-lived access token](https://developers.home-assistant.io/docs/auth_api/#long-lived-access-token)

## Setup

```bash
git clone https://github.com/mikeoc61/rheem_water_heater.git
cd rheem_water_heater
echo 'HA_TOKEN=<your token>' > .env
chmod 600 .env
```

Each script looks for `.env` in the directory it was run from (following
the path you invoked, so a symlink in `~/bin` reads `~/bin/.env`), then
falls back to `~/.env`. `.env` is in `.gitignore`.

To run them from anywhere, symlink them onto your `PATH`:

```bash
ln -s "$PWD/eco-status.sh" "$PWD/eco-run-history.sh" ~/bin/
```

## Usage

```bash
./eco-status.sh
```

```text
===== EcoNet Water Heater Snapshot =====
Timestamp        : Wed Nov 25 01:23:41 PM HST 2026

--- Operation ---
Mode             : eco
Running          : off
Running State    :

--- Hot Water ---
Available        : 100%

--- Daily Usage ---
Power Today      : 1.7 kWh

--- Health ---
Compressor       : 100%
Tank             : 100%
Alerts           : 0
```

```bash
./eco-run-history.sh              # since the 1st of this month
./eco-run-history.sh 2026-11-20   # since a date
./eco-run-history.sh "7 days ago" # anything GNU date understands
```

```text
Heat pump water heater — run history
Current mode: eco
Period: Nov 25, 2026 00:00–Nov 25, 2026 13:18 (HST)

Energy estimate: compressor 500 W (assumed), element 4500 W (rated)

Started                Run time             Previous idle   Mode at start   Est. kWh
Nov 25, 2026 09:42 AM  29m                  9h 42m          eco             1.45
Nov 25, 2026 11:12 AM  1h 02m               59m             eco             0.52

Runs: 2   Total runtime: 1h 32m   Estimated energy: 1.97 kWh
```

Energy is estimated from which component (compressor, element or both) the
heater reported running, multiplied by its wattage. A `+*` after a figure
means component history was missing for part of a run, so the figure is a
lower bound. Output is colored on a terminal; set `NO_COLOR=1` to turn that
off.

## Configuration

| Variable | Default | Used by |
|---|---|---|
| `HA_TOKEN` | — (required) | both |
| `HA_URL` | `http://localhost:8123` | both |
| `ENV_FILE` | `.env` beside the script, then `~/.env` | both |
| `COMPRESSOR_WATTS` | `500` (assumed; measure your unit) | `eco-run-history.sh` |
| `ELEMENT_WATTS` | `4500` (rated) | `eco-run-history.sh` |

## Home Assistant entities

The scripts read these entities; rename them in the scripts if your
integration named them differently.

- `water_heater.heat_pump_water_heater`
- `binary_sensor.heat_pump_water_heater_running`
- `sensor.heat_pump_water_heater_running_state`
- `sensor.heat_pump_water_heater_available_hot_water`
- `sensor.heat_pump_water_heater_power_usage_today`
- `sensor.heat_pump_water_heater_compressor_health`
- `sensor.heat_pump_water_heater_tank_health`
- `sensor.heat_pump_water_heater_alert_count`

Run history comes from Home Assistant's recorder, so it only goes back as
far as your recorder keeps data (10 days by default).
