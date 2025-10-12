# External Event Integration Examples

Doubar includes an HTTP event server that allows external applications, scripts, and tools to send events to the app. This works in both development and production modes.

## Server Configuration

- **Default Port**: `3030`
- **Fallback**: Automatically tries ports 3031-3039 if 3030 is occupied
- **Endpoint**: `POST http://127.0.0.1:3030/events`

## Event Format

Events are sent as JSON with the following structure:

```json
{
  "type": "event-type-name",
  "data": {
    "key": "value"
  }
}
```

## Usage Examples

### 1. Using curl (Command Line)

```bash
# Simple refresh event
curl -X POST http://127.0.0.1:3030/events \
  -H "Content-Type: application/json" \
  -d '{"type":"refresh","data":{}}'

# Event with data
curl -X POST http://127.0.0.1:3030/events \
  -H "Content-Type: application/json" \
  -d '{"type":"focus","data":{"workspace":"1"}}'
```

### 2. Using the Shell Script

Make the script executable:
```bash
chmod +x examples/send-event.sh
```

Use it:
```bash
# Send refresh event
./examples/send-event.sh refresh

# Send focus event
./examples/send-event.sh focus

# Send custom event
./examples/send-event.sh custom my-event '{"foo":"bar"}'
```

### 3. Using AppleScript

Run the AppleScript directly:
```bash
osascript examples/send-event.applescript
```

Or open it in Script Editor and customize the events you want to send.

### 4. From Other Languages

#### Python
```python
import requests

def send_event(event_type, data=None):
    url = "http://127.0.0.1:3030/events"
    payload = {"type": event_type, "data": data or {}}
    response = requests.post(url, json=payload)
    return response.json()

send_event("refresh")
send_event("focus", {"workspace": "1"})
```

#### JavaScript/Node.js
```javascript
async function sendEvent(eventType, data = {}) {
  const response = await fetch('http://127.0.0.1:3030/events', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: eventType, data })
  });
  return response.json();
}

sendEvent('refresh');
sendEvent('focus', { workspace: '1' });
```

## Adding Custom Event Handlers

Edit `src/App.tsx` to handle your custom event types:

```typescript
useEffect(() => {
  const unlisten = listen<{ type: string; data: any }>("external-event", (event) => {
    console.log("Received external event:", event.payload);

    switch (event.payload.type) {
      case "your-custom-event":
        // Handle your custom event here
        console.log("Custom event data:", event.payload.data);
        break;
      // Add more cases as needed
    }
  });

  return () => {
    unlisten.then(fn => fn());
  };
}, []);
```

## Use Cases

1. **Automation Scripts**: Trigger app actions from cron jobs or automation tools
2. **Alfred/Raycast Workflows**: Create custom workflows that control your app
3. **AppleScript Integration**: Integrate with macOS automation
4. **Custom CLI Tools**: Build command-line tools that interact with your app
5. **Inter-App Communication**: Allow other apps to send commands to Doubar

## Troubleshooting

### Server Not Starting

Check the console output when starting the app. It will show which port the server is running on:
```
Event server listening on http://127.0.0.1:3030
```

### Connection Refused

Make sure:
1. The app is running
2. You're using the correct port (check console output)
3. No firewall is blocking localhost connections

### Events Not Being Received

1. Check the app console for "Received external event:" messages
2. Verify your JSON payload is valid
3. Ensure the Content-Type header is set to `application/json`
