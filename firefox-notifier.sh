#!/bin/bash

#
# Depends: loginctl, tr, pgrep, strings, su, notify-send, firefox-updater.sh
#
if [[ $EUID -ne 0 ]]; then
    echo "Not allowed to execute as normal user!"
    exit 1
fi

# CONFIG:
#
FIREFOX_UPDATER=/opt/bin/firefox-updater.sh
#

shopt -s extglob

# Parse session properties from logged in users.
read -ra b < <( \
    loginctl show-seat seat0 -P Sessions --no-legend \
)
mapfile -t < <(loginctl show-session "${b[@]}" -p Name -p Display -p Type --all | tr -s \\n)

# Match users with x11 session.
declare -A A
((c=${#MAPFILE[@]} / ${#b[@]}))
for ((d=0, e=0; d < ${#b[@]}; d++, e+=c)); do
    A=()
    for f in "${MAPFILE[@]:$e:$c}"; do
        [[ $f =~ ^([^=]+)=(.*)$ ]] && \
        A[${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}
    done
    if [[ ${A[Type]} = @(x11|wayland) ]]; then
        read -r ppid < <( \
            pgrep -P 1 -U "${A[Name]}" -f 'systemd[[:space:]].*--user' ) || exit 0
        read -r bpid < <( \
            pgrep -P "$ppid" -U "${A[Name]}" -f '(dbus-daemon[[:space:]].*--session|dbus-broker-launch[[:space:]].*--scope[[:space:]]user)' ) || exit 0

        # shellcheck disable=SC1090
        source <(strings "/proc/$bpid/environ")

        [[ -n $DBUS_SESSION_BUS_ADDRESS ]] || exit 1

        # Notify logged in user on new firefox version.
        # shellcheck disable=SC2016
        if $FIREFOX_UPDATER; then
            su "${A[Name]}" -c 'notify-send -t 0 -a "Firefox Updater" "Version: $1" "A new firefox version has been released."' _ "$(firefox --version)"
        fi
    fi
done
