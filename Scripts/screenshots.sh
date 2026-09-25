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

# The panel is translucent, so whatever is behind it bleeds through, blurred.
# A plain dark window under it (below the panel's level, above everything else)
# keeps the desktop out of the pictures without touching any other app.
tmp=$(mktemp -d)
swiftc -O -o "$tmp/backdrop" - <<'EOF' 2>/dev/null
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSScreen.main!.frame, styleMask: .borderless,
                      backing: .buffered, defer: false)
window.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1)
window.level = .floating
window.ignoresMouseEvents = true
window.collectionBehavior = [.canJoinAllSpaces, .stationary]
window.orderFrontRegardless()
app.run()
EOF
"$tmp/backdrop" & backdrop=$!
trap 'kill $backdrop 2>/dev/null; rm -rf "$tmp"' EXIT
sleep 1

# The pointer resting on a row would show as a hover highlight and a scrollbar.
swift - <<'EOF' 2>/dev/null
import AppKit
let frame = NSScreen.main!.frame
CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: frame.height - 4))
EOF

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
	# The scroll indicator flashes when a list appears; give it time to fade.
	sleep 2
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
sleep 2.5
capture moments
se 'keystroke "1" using command down' >/dev/null
sleep 0.3
se 'key code 53' >/dev/null
