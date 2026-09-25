if [ -f ~/.cache/brightness_level ]; then
	brightnessctl set "$(cat ~/.cache/brightness_level)"
fi

if [ -f "$HOME/.cache/colors/wallpaper" ]; then
    swaybg -i "$(cat "$HOME/.cache/colors/wallpaper")" -m fill &
fi

/usr/libexec/polkit-mate-authentication-agent-1 &
redshift &
~/scripts/start-maybar.sh &
wlsunset -l 53.5 -L -113.5 &


