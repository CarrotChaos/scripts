#!/usr/bin/env bash

LAT=
LON=

JSON=$(curl -s "https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&current=temperature_2m,apparent_temperature,weather_code&timezone=auto")

if [[ -z "$JSON" || "$JSON" = *"error"* ]]; then
	echo " --°C"
	exit 1
fi

read -r TEMP FEELS CODE < <(echo "$JSON" | jq -r '.current | "\(.temperature_2m) \(.apparent_temperature) \(.weather_code)"')

# Optional: round temperature
# TEMP=$(printf "%.0f" "$TEMP")

# ────────────────────────────────────────
#          More descriptive icons
# ────────────────────────────────────────

case $CODE in
# ── Clear ───────────────────────────────────────
0) ICON="󰖙" ;; # nf-weather-day_sunny           (clear day)
# ── Mainly clear / partly cloudy ────────────────
1) ICON="󰖚" ;; # nf-weather-day_sunny_overcast
2) ICON="󰖜" ;; # nf-weather-day_cloudy
3) ICON="󰖝" ;; # nf-weather-cloudy             (overcast)

# ── Fog ─────────────────────────────────────────
45 | 48) ICON="󰖑" ;; # nf-weather-fog

# ── Drizzle ─────────────────────────────────────
51 | 53 | 55 | 56 | 57) ICON="󰖗" ;; # nf-weather-sprinkle / day_sprinkle

# ── Rain ────────────────────────────────────────
61 | 63 | 80 | 81) ICON="󰖖" ;; # nf-weather-rain / day_rain
65 | 82) ICON="󰖞" ;;           # nf-weather-rain_windy / heavy

# ── Snow ────────────────────────────────────────
71 | 73 | 75 | 77 | 85 | 86) ICON="󰼶" ;; # nf-weather-snow               (or  if you prefer)

# ── Thunder ─────────────────────────────────────
95 | 96 | 99) ICON="󰖝󱐋" ;; # cloudy + lightning (󰖝 = nf-weather-thunderstorm)

# fallback
*) ICON="" ;;
esac

# Optional: day / night version (requires is_day from API)
# Add to curl:   &current=is_day
# Then:
# read -r TEMP FEELS CODE IS_DAY < <(jq -r '.current | "\(.temperature_2m) \(.apparent_temperature) \(.weather_code) \(.is_day)"' )
# and choose e.g. 󰖙 vs 󰖛 (day_sunny vs night_clear)

echo "$ICON ${TEMP}°C (feels ${FEELS}°C)"
