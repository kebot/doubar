import { useState, useEffect } from "react";
import "./App.css";
import AeroSpace from "./widgets/AeroSpace";

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
  return (
    <main className="container font-mono text-sm text-white">
      &gt; Taubar
      <AeroSpace />
      <TimeWidget />
    </main>
  );
}

export default App;
