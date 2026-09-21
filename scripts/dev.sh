#!/usr/bin/env bash
# Run `bun tauri dev` and restart it whenever it dies — e.g. after the Mac
# wakes from sleep, which tears down Vite's watchers and HMR socket.
#
# Ctrl-C exits for real instead of triggering a restart. A crash loop (several
# exits in a row within MIN_UPTIME, typically a compile error) also gives up
# rather than spinning.

set -u

RESTART_DELAY=${RESTART_DELAY:-2}
MIN_UPTIME=${MIN_UPTIME:-10}
MAX_FAST_FAILURES=${MAX_FAST_FAILURES:-3}

child=""
stopping=0

cleanup() {
	stopping=1
	[ -n "$child" ] && kill -TERM "$child" 2>/dev/null
}
trap cleanup INT TERM

fast_failures=0
while true; do
	killall doubar 2>/dev/null || true

	started=$SECONDS
	bun tauri dev &
	child=$!
	wait "$child"
	code=$?
	child=""
	ran=$((SECONDS - started))

	if [ "$stopping" -eq 1 ]; then
		echo "→ stopped"
		exit 0
	fi

	[ "$code" -eq 0 ] && exit 0

	if [ "$ran" -lt "$MIN_UPTIME" ]; then
		fast_failures=$((fast_failures + 1))
		if [ "$fast_failures" -ge "$MAX_FAST_FAILURES" ]; then
			echo "→ exited ($code) after ${ran}s, $fast_failures times in a row — giving up"
			exit "$code"
		fi
	else
		fast_failures=0
	fi

	echo "→ exited ($code) after ${ran}s — restarting in ${RESTART_DELAY}s (Ctrl-C to stop)"
	sleep "$RESTART_DELAY"
done
