#!/bin/bash

# Show water heater run history. Pass a start date understood by GNU date.
set -o pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Prefer a .env next to the script; fall back to ~/.env.
env_file=${ENV_FILE:-$script_dir/.env}
[[ -f $env_file ]] || env_file=$HOME/.env
if [[ ! -f $env_file ]]; then
    printf 'No .env found in %s or %s\n' "$script_dir" "$HOME" >&2
    exit 1
fi
source "$env_file"
if [[ -z ${HA_TOKEN:-} ]]; then
    printf 'HA_TOKEN not set in %s\n' "$env_file" >&2
    exit 1
fi
ha_url=${HA_URL:-http://localhost:8123}

start_input=${1:-"$(date +%Y-%m-01)"}
if ! start_epoch=$(date -d "$start_input" +%s 2>/dev/null); then
    printf 'Invalid start date: %s\n' "$start_input" >&2
    exit 1
fi
now_epoch=$(date +%s)
if (( start_epoch > now_epoch )); then
    printf 'Start date must not be in the future: %s\n' "$start_input" >&2
    exit 1
fi
start_iso=$(date -d "@$start_epoch" +%Y-%m-%dT%H:%M:%S%:z)
end_iso=$(date -d "@$now_epoch" +%Y-%m-%dT%H:%M:%S%:z)

running_entity=binary_sensor.heat_pump_water_heater_running
mode_entity=water_heater.heat_pump_water_heater
component_entity=sensor.heat_pump_water_heater_running_state

# One history request covers all three entities; the reply holds one list per
# entity. With minimal_response only each list's first row has an entity_id.
if ! response=$(curl -fsS --max-time 30 -G -H "Authorization: Bearer $HA_TOKEN" \
    --data-urlencode "end_time=$end_iso" \
    --data-urlencode "filter_entity_id=$running_entity,$mode_entity,$component_entity" \
    --data-urlencode 'minimal_response' --data-urlencode 'no_attributes' \
    "$ha_url/api/history/period/$start_iso"); then
    printf 'Could not retrieve water heater history from Home Assistant.\n' >&2
    exit 1
fi
if ! jq -e 'type == "array" and all(.[]; type == "array")' >/dev/null 2>&1 <<< "$response"; then
    printf 'Home Assistant returned an invalid history response.\n' >&2
    exit 1
fi

# Rows of the list belonging to entity $id.
rows='.[] | select(.[0].entity_id == $id) | .[] | select(.last_changed != null)'
events=$(jq -r --arg id "$running_entity" "$rows"' | select(.state == "on" or .state == "off") | [.last_changed, .state] | @tsv' <<< "$response")
# Mode and component history are optional: if absent, runs still show.
mode_events=$(jq -r --arg id "$mode_entity" "$rows"' | [.last_changed, "mode", .state] | @tsv' <<< "$response")
# Component history supports estimates based on what actually ran.
component_events=$(jq -r --arg id "$component_entity" "$rows"' | [.last_changed, "component", (.state // "")] | @tsv' <<< "$response")

# Compressor power varies with conditions; override after measuring your unit.
compressor_watts=${COMPRESSOR_WATTS:-500}
element_watts=${ELEMENT_WATTS:-4500}
if [[ ! $compressor_watts =~ ^[0-9]+([.][0-9]+)?$ || ! $element_watts =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    printf 'COMPRESSOR_WATTS and ELEMENT_WATTS must be non-negative numbers.\n' >&2
    exit 1
fi

# The water heater entity's state is its current operating mode.
mode=$(curl -fsS --max-time 15 -H "Authorization: Bearer $HA_TOKEN" \
    "$ha_url/api/states/$mode_entity" | \
    jq -er '.state | select(type == "string" and length > 0)' 2>/dev/null) || mode='unavailable'

bold='' dim='' green='' cyan='' yellow='' magenta='' reset=''
if [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
    bold=$'\e[1m' dim=$'\e[2m' green=$'\e[1;32m'
    cyan=$'\e[36m' yellow=$'\e[33m' magenta=$'\e[35m' reset=$'\e[0m'
fi

printf '%sHeat pump water heater — run history%s\n' "$bold" "$reset"
case $mode in high_demand) mode=high-demand;; electric) mode=element;; heat_pump) mode=heat-pump;; esac
case $mode in
    heat-pump) mode_color=$cyan;;
    element) mode_color=$yellow;;
    high-demand) mode_color=$magenta;;
    unavailable | unknown) mode_color=$dim;;
    *) mode_color='';;
esac
printf 'Current mode: %s%s%s\n' "$mode_color" "$mode" "$reset"
printf 'Period: %s–%s (%s)\n\n' "$(date -d "@$start_epoch" '+%b %-d, %Y %H:%M')" "$(date -d "@$now_epoch" '+%b %-d, %Y %H:%M')" "$(date -d "@$now_epoch" +%Z)"
if [[ -z $events ]]; then
    printf 'No on/off history found for this period.\n'
    exit 0
fi
printf 'Energy estimate: compressor %s W (assumed), element %s W (rated)\n\n' "$compressor_watts" "$element_watts"
printf '%s%-22s %-20s %-15s %-15s %s%s\n' "$bold" 'Started' 'Run time' 'Previous idle' 'Mode at start' 'Est. kWh' "$reset"

while IFS=$'\t' read -r ts state value; do
    epoch=$(date -d "$ts" +%s 2>/dev/null) || continue
    printf '%s %s %s\n' "$epoch" "$state" "$value"
done <<< "$mode_events"$'\n'"$component_events"$'\n'"$events" | sort -s -k1,1n | awk -v now="$now_epoch" \
    -v bold="$bold" -v dim="$dim" -v green="$green" -v reset="$reset" \
    -v cyan="$cyan" -v yellow="$yellow" -v magenta="$magenta" \
    -v compressor_watts="$compressor_watts" -v element_watts="$element_watts" '
function duration(seconds, minutes, hours) {
    minutes = int(seconds / 60); hours = int(minutes / 60); minutes %= 60
    return hours ? sprintf("%dh %02dm", hours, minutes) : sprintf("%dm", minutes)
}
function accrue(end) {
    if (start && end > segment_start) {
        if (component == "compressor" || component == "both") energy += (end - segment_start) * compressor_watts / 3600000
        if (component == "element" || component == "both") energy += (end - segment_start) * element_watts / 3600000
        if (component == "unknown" || component == "" || component == "off") incomplete = 1
    }
    segment_start = end
}
function row(end, active, label, runtime, mode_color, idle_cell, energy_cell) {
    accrue(end)
    energy_cell = incomplete ? sprintf("%.2f+*", energy) : sprintf("%.2f", energy)
    if (incomplete) any_incomplete = 1
    total_energy += energy
    label = duration(end - start)
    runtime = sprintf("%-20s", label)
    if (active) {
        runtime = sprintf("%-20s", label " (running)")
        sub(/\(running\)/, green "(running)" reset, runtime)
    }
    mode_color = run_mode == "heat-pump" ? cyan : (run_mode == "element" ? yellow : (run_mode == "high-demand" ? magenta : (run_mode == "unknown" ? dim : "")))
    idle_cell = idle == "—" ? dim idle reset sprintf("%14s", "") : sprintf("%-15s", idle)
    cmd = "date -d @" start " '\''+%b %-d, %Y %I:%M %p'\''"
    cmd | getline started; close(cmd)
    printf "%-22s %s %s %s%-15s%s %s\n", started, runtime, idle_cell, mode_color, run_mode, reset, energy_cell
    total += end - start; count++
}
$2 == "mode" {
    mode = $3 == "high_demand" ? "high-demand" : ($3 == "electric" ? "element" : ($3 == "heat_pump" ? "heat-pump" : $3))
    next
}
$2 == "component" {
    accrue($1)
    raw = tolower($0)
    if (raw ~ /unavailable|unknown/) component = "unknown"
    else if (raw ~ /compressor/ && raw ~ /element/) component = "both"
    else if (raw ~ /compressor/) component = "compressor"
    else if (raw ~ /element/) component = "element"
    else if (NF == 2) component = "off"
    else component = "unknown"
    next
}
$2 == "on" && !start {
    run_mode = mode == "" || mode == "unavailable" ? "unknown" : mode
    start = $1; segment_start = $1; energy = 0; incomplete = 0
    idle = last_off ? duration(start - last_off) : "—"
}
$2 == "off" {
    if (start) { row($1, 0); start = 0 }
    last_off = $1
}
END {
    if (start) row(now, 1)
    if (count) {
        printf "\n%sRuns: %d   Total runtime: %s   Estimated energy: %.2f%s kWh%s\n", bold, count, duration(total), total_energy, any_incomplete ? "+*" : "", reset
        if (any_incomplete) print "* Component history incomplete; shown energy is a partial estimate."
    }
    else print "No runs found for this period."
}'
