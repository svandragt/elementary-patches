#!/bin/bash
# restart.sh — restart a package's systemd user service in place
# Usage: ./restart.sh <package>

set -euo pipefail

PACKAGE="${1:-}"

if [[ -z "$PACKAGE" ]]; then
    echo "Usage: ep restart <package>" >&2
    exit 1
fi

# Only packages that run as a session service can be restarted this way.
case "$PACKAGE" in
    gala) UNIT="io.elementary.gala@${XDG_SESSION_TYPE:-x11}.service" ;;
    *)    UNIT="" ;;
esac

if [[ -z "$UNIT" ]]; then
    echo "No service mapping for '$PACKAGE' — restart it yourself." >&2
    exit 1
fi

if [[ "$(systemctl --user is-active "$UNIT" 2>/dev/null)" != "active" ]]; then
    echo "$UNIT is not active." >&2
    exit 1
fi

OLD_PID=$(systemctl --user show "$UNIT" -p MainPID --value)

# The unit allows 3 starts per 15s and fails the session on the 4th, so refuse
# to spend a second one inside that window.
STARTED=$(date -d "$(systemctl --user show "$UNIT" -p ExecMainStartTimestamp --value)" +%s)
UP=$(( $(date +%s) - STARTED ))
if (( UP < 15 )); then
    echo "$UNIT started ${UP}s ago. Wait $(( 15 - UP ))s — three starts in 15s fails the session." >&2
    exit 1
fi

echo "Restarting $UNIT (pid $OLD_PID)..."
# RefuseManualStop=on blocks 'systemctl stop|restart', but not 'kill'.
# Restart=always brings it back with RestartSec=0.
systemctl --user kill --signal=TERM "$UNIT"

for _ in $(seq 30); do
    sleep 0.5
    NEW_PID=$(systemctl --user show "$UNIT" -p MainPID --value)
    if [[ "$NEW_PID" != "$OLD_PID" && "$NEW_PID" != "0" ]]; then
        echo "Restarted: $OLD_PID -> $NEW_PID"
        exit 0
    fi
done

echo "$UNIT did not come back. Check: systemctl --user status $UNIT" >&2
exit 1
