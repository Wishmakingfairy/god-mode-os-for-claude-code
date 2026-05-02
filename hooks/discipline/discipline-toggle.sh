#!/bin/bash
# discipline-toggle.sh — Kill switch for all god-mode-os hooks.
# Usage:
#   discipline-toggle.sh off    # disable all hooks
#   discipline-toggle.sh on     # re-enable all hooks
#   discipline-toggle.sh status # show current state

KILL_SWITCH="${GMOS_KILL_SWITCH:-$HOME/.claude/.god-mode-disabled}"

case "${1:-status}" in
    off|disable)
        mkdir -p "$(dirname "$KILL_SWITCH")"
        touch "$KILL_SWITCH"
        echo "god-mode-os hooks DISABLED. Touched: $KILL_SWITCH"
        ;;
    on|enable)
        rm -f "$KILL_SWITCH"
        echo "god-mode-os hooks ENABLED. Removed: $KILL_SWITCH"
        ;;
    status)
        if [ -f "$KILL_SWITCH" ]; then
            echo "DISABLED (kill switch present at $KILL_SWITCH)"
        else
            echo "ENABLED (no kill switch at $KILL_SWITCH)"
        fi
        ;;
    *)
        echo "Usage: $0 {on|off|status}"
        exit 1
        ;;
esac
