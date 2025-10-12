import { useState, useEffect } from "react";
import "./App.css";
import AeroSpace from "./widgets/AeroSpace";
import { listen } from "@tauri-apps/api/event";

function TimeWidget () {
  const [time, setTime] = useState(new Date());
  useEffect(() => {
    const interval = setInterval(() => {
      setTime(new Date());
    }, 1000);
    return () => clearInterval(interval);
  }, []);

  return (
    <span className="ml-1 text-xs text-gray-200">
      &nbsp; {time.toLocaleString()}
    </span>
  )
}

function App() {
  useEffect(() => {
    // Listen for external events from HTTP server
    const unlisten = listen<{ type: string; data: any }>("external-event", (event) => {
      console.log("Received external event:", event.payload);

      // Handle different event types
      switch (event.payload.type) {
        case "refresh":
          console.log("Refresh requested");
          // Add your refresh logic here
          break;
        case "focus":
          console.log("Focus requested with data:", event.payload.data);
          // Add your focus logic here
          break;
        default:
          console.log("Unknown event type:", event.payload.type);
      }
    });

    return () => {
      unlisten.then(fn => fn());
    };
  }, []);

  return (
    <main className="font-mono text-sm text-white w-full h-[var(--bar-height)] bg-background/5 px-4 flex justify-between items-center gap-1">
      <AeroSpace />
      <TimeWidget />
    </main>
  );
}

export default App;
