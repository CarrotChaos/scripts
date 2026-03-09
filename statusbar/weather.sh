#!/bin/sh
curl -sf "wttr.in/?format=%c+%t+(%f)" | sed 's/  */ /g'
