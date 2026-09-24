#!/bin/sh
# Regenerates docs/stations.png and docs/moments.png from the running app.
#
# Opens the panel through Accessibility and captures its window, so the images
# are the real panel, not mockups. The terminal running this needs two
# permissions in System Settings → Privacy & Security: Accessibility (to open
# the panel) and Screen Recording (to capture it).
set -eu
cd "$(dirname "$0")/.."
mkdir -p docs

pgrep -qf "Skywave.app/Contents/MacOS/Skywave" || { echo "Skywave is not running"; exit 1; }

open_panel() {
	osascript -e 'tell application "System Events" to tell process "Skywave" to perform action "AXPress" of (first menu bar item of menu bar 2)' >/dev/null
	sleep 1.5
}

# The panel is the only 344-wide window the app has.
panel_id() {
	swift - <<'EOF'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Skywave" {
    let b = w[kCGWindowBounds as String] as! [String: Double]
    if Int(b["W"]!) == 344 { print(w[kCGWindowNumber as String]!); break }
}
EOF
}

capture() {
	id=$(panel_id)
	[ -n "$id" ] || { echo "panel window not found"; exit 1; }
	screencapture -x -o -l "$id" "docs/$1.png"
	echo "docs/$1.png"
}

open_panel
capture stations
osascript -e 'tell application "System Events" to tell process "Skywave" to keystroke "2" using command down' >/dev/null
sleep 0.8
capture moments
osascript -e 'tell application "System Events" to tell process "Skywave" to keystroke "1" using command down' >/dev/null
sleep 0.3
osascript -e 'tell application "System Events" to tell process "Skywave" to key code 53' >/dev/null
