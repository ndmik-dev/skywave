#!/bin/sh
# Regenerates docs/stations.png and docs/moments.png from the running app.
#
# Opens the panel through Accessibility and captures the region it occupies,
# so the images are the real panel, not mockups. The terminal running this
# needs two permissions in System Settings → Privacy & Security: Accessibility
# (to open the panel) and Screen Recording (to capture it).
#
# Start a station first: a panel with nothing on air makes a poor picture.
set -eu
cd "$(dirname "$0")/.."
mkdir -p docs

pgrep -qf "Skywave.app/Contents/MacOS/Skywave" || { echo "Skywave is not running"; exit 1; }

se() { osascript -e "tell application \"System Events\" to tell process \"Skywave\" to $1"; }

# AXPress toggles the panel, so pressing once may just as well close it if it
# was already open. Press, and press again if no window appeared.
open_panel() {
	se 'perform action "AXPress" of (first menu bar item of menu bar 2)' >/dev/null
	sleep 1.2
	if [ "$(se 'get count of windows')" = "0" ]; then
		se 'perform action "AXPress" of (first menu bar item of menu bar 2)' >/dev/null
		sleep 1.2
	fi
}

# The panel's frame comes from Accessibility, in the same screen points that
# screencapture -R takes; CGWindowList is not relied on, since it may hide
# other apps' windows depending on what the shell has been granted.
capture() {
	frame=$(se 'get {position, size} of window 1' | tr -d ' ')
	[ -n "$frame" ] || { echo "panel window not found"; exit 1; }
	screencapture -x -o -R "$frame" "docs/$1.png"
	echo "docs/$1.png  ($frame)"
}

open_panel
capture stations
se 'keystroke "2" using command down' >/dev/null
sleep 0.8
capture moments
se 'keystroke "1" using command down' >/dev/null
sleep 0.3
se 'key code 53' >/dev/null
