#!/bin/sh
# Build HatariMidiBridge and keep it running in the background as a LaunchAgent.
#
#   scripts/install-bridge.sh              build, install and start it (it also starts at every login)
#   scripts/install-bridge.sh --uninstall  stop it and remove the agent and the program
#   scripts/install-bridge.sh --dry-run    show what would be installed, change nothing
#
# The program is a universal binary (arm64 and x86_64) copied to
# ~/Library/Application Support/HatariMidiBridge. It lives outside the
# project folder on purpose: the folder is shared between Macs through
# iCloud, but the agent belongs to this Mac. Its output goes to
# ~/Library/Logs/HatariMidiBridge.log.

set -eu
cd "$(dirname "$0")/.."

label="io.github.zrhbert.HatariMidiBridge"
support="$HOME/Library/Application Support/HatariMidiBridge"
program="$support/HatariMidiBridge"
plist="$HOME/Library/LaunchAgents/$label.plist"
log="$HOME/Library/Logs/HatariMidiBridge.log"
domain="gui/$(id -u)"

mode=install
case "${1:-}" in
    "") ;;
    --uninstall) mode=uninstall ;;
    --dry-run) mode=dry-run ;;
    *) echo "usage: $0 [--uninstall | --dry-run]" >&2; exit 2 ;;
esac

write_plist() {
    cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$program</string>
        <string>--quiet</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>5</integer>
    <key>StandardOutPath</key><string>$log</string>
    <key>StandardErrorPath</key><string>$log</string>
</dict>
</plist>
PLIST
}

case "$mode" in
dry-run)
    echo "program: $program"
    echo "agent:   $plist"
    echo "log:     $log"
    echo "---"
    write_plist
    ;;
uninstall)
    launchctl bootout "$domain/$label" 2>/dev/null || true
    rm -f "$plist"
    rm -rf "$support"
    echo "removed $label"
    ;;
install)
    swift build -c release --arch arm64 --arch x86_64 --product HatariMidiBridge
    binary="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/HatariMidiBridge"

    mkdir -p "$support" "$(dirname "$plist")" "$(dirname "$log")"
    # Stop the running copy before replacing its file.
    launchctl bootout "$domain/$label" 2>/dev/null || true
    cp "$binary" "$program"
    codesign --force --sign - "$program" >/dev/null 2>&1
    write_plist > "$plist"
    plutil -lint "$plist" >/dev/null
    launchctl bootstrap "$domain" "$plist"
    echo "installed $label ($(lipo -archs "$program")); log: $log"
    ;;
esac
