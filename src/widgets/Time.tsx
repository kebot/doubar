import { useEffect, useState } from "react"
import { Pill } from "../components/Bar"

export function TimeWidget() {
  const [time, setTime] = useState(new Date())
  useEffect(() => {
    const interval = setInterval(() => {
      setTime(new Date())
    }, 1000)
    return () => clearInterval(interval)
  }, [])

  return <Pill className="bg-background text-foreground text-sm">&nbsp; {time.toLocaleString()}</Pill>
}