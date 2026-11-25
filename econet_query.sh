#!/bin/bash
# econet_query.sh — Rheem EcoNet Heat Pump Water Heater snapshot via Home Assistant
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Prefer a .env next to the script; fall back to ~/.env (used by eco-run-history.sh).
ENV_FILE="${ENV_FILE:-${SCRIPT_DIR}/.env}"
[[ -f "${ENV_FILE}" ]] || ENV_FILE="${HOME}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: no .env found in ${SCRIPT_DIR} or ${HOME}" >&2
  exit 1
fi
source "${ENV_FILE}"

if [[ -z "${HA_TOKEN}" ]]; then
  echo "ERROR: HA_TOKEN not set in ${ENV_FILE}" >&2
  exit 1
fi

HA_URL="${HA_URL:-http://localhost:8123}"

# One request for all states; individual lookups happen locally.
if ! STATES=$(curl -fsS --max-time 15 \
    -H "Authorization: Bearer ${HA_TOKEN}" \
    "${HA_URL}/api/states"); then
  echo "ERROR: could not retrieve states from Home Assistant at ${HA_URL}" >&2
  exit 1
fi
if ! jq -e 'type == "array"' >/dev/null 2>&1 <<< "${STATES}"; then
  echo "ERROR: Home Assistant returned an invalid states response" >&2
  exit 1
fi

get_state() {
  jq -r --arg id "$1" \
    'first(.[] | select(.entity_id == $id) | .state | select(. != null)) // "unavailable"' \
    <<< "${STATES}"
}

# Append a unit only to numeric values, so "unavailable" doesn't become "unavailable%".
with_unit() {
  if [[ $1 =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    printf '%s%s' "$1" "$2"
  else
    printf '%s' "$1"
  fi
}

MODE=$(get_state water_heater.heat_pump_water_heater)
RUNNING=$(get_state binary_sensor.heat_pump_water_heater_running)
RUNNING_STATE=$(get_state sensor.heat_pump_water_heater_running_state)
AVAILABLE_HOT=$(get_state sensor.heat_pump_water_heater_available_hot_water)
POWER_TODAY=$(get_state sensor.heat_pump_water_heater_power_usage_today)
COMPRESSOR_HEALTH=$(get_state sensor.heat_pump_water_heater_compressor_health)
TANK_HEALTH=$(get_state sensor.heat_pump_water_heater_tank_health)
ALERT_COUNT=$(get_state sensor.heat_pump_water_heater_alert_count)

echo "===== EcoNet Water Heater Snapshot ====="
echo "Timestamp        : $(date)"
echo ""
echo "--- Operation ---"
echo "Mode             : ${MODE}"
echo "Running          : ${RUNNING}"
echo "Running State    : ${RUNNING_STATE}"
echo ""
echo "--- Hot Water ---"
echo "Available        : $(with_unit "${AVAILABLE_HOT}" %)"
echo ""
echo "--- Daily Usage ---"
echo "Power Today      : $(with_unit "${POWER_TODAY}" " kWh")"
echo ""
echo "--- Health ---"
echo "Compressor       : $(with_unit "${COMPRESSOR_HEALTH}" %)"
echo "Tank             : $(with_unit "${TANK_HEALTH}" %)"
echo "Alerts           : ${ALERT_COUNT}"
if [[ ${ALERT_COUNT} =~ ^[0-9]+([.][0-9]+)?$ ]] && (( ${ALERT_COUNT%%.*} > 0 )); then
  echo "  ^^^ Check EcoNet app for alert detail"
fi
