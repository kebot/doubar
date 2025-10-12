#!/bin/bash

# Example shell script to send events to Doubar

# Configuration
PORT=${DOUBAR_PORT:-3030}
HOST="127.0.0.1"
URL="http://${HOST}:${PORT}/events"

# Function to send event
send_event() {
    local event_type="$1"
    local event_data="${2:-{}}"

    curl -s -X POST "$URL" \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"$event_type\",\"data\":$event_data}" \
        || echo "Failed to send event"
}

# Example usage
case "${1:-help}" in
    refresh)
        echo "Sending refresh event..."
        send_event "refresh"
        ;;
    focus)
        echo "Sending focus event..."
        send_event "focus" '{"workspace":"1"}'
        ;;
    custom)
        echo "Sending custom event..."
        send_event "${2:-custom}" "${3:-{}}"
        ;;
    help|*)
        echo "Usage: $0 {refresh|focus|custom [type] [data]}"
        echo ""
        echo "Examples:"
        echo "  $0 refresh"
        echo "  $0 focus"
        echo "  $0 custom my-event '{\"key\":\"value\"}'"
        echo ""
        echo "Or use directly:"
        echo "  curl -X POST http://127.0.0.1:3030/events -H 'Content-Type: application/json' -d '{\"type\":\"refresh\",\"data\":{}}'"
        ;;
esac
