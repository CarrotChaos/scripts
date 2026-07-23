#!/bin/bash

cat >~/.xbindkeysrc <<'EOF'
"xdotool key 9"
    b:8
EOF

pkill xbindkeys 2>/dev/null
xbindkeys

echo "Side mouse button (Button 8) now sends the 9 key."
