import { createContext, useContext, useEffect, useState } from 'react'
import { getCurrentWindow, currentMonitor, primaryMonitor, availableMonitors } from '@tauri-apps/api/window'
import type { PhysicalPosition, PhysicalSize } from '@tauri-apps/api/dpi'
import { Command } from '@tauri-apps/plugin-shell'

export interface AeroSpaceMonitorInfo {
  monitorId: number
  monitorName: string
}

export interface ScreenInfo {
  screenIndex: number
  monitorName: string | null
  screenSize: PhysicalSize
  workArea: { position: PhysicalPosition; size: PhysicalSize }
  scaleFactor: number
  isPrimary: boolean
  hasNotch: boolean
  aerospace: AeroSpaceMonitorInfo | null
}

function getScreenIndex(): number {
  try {
    const label = getCurrentWindow().label // e.g. "bar_1"
    const m = label.match(/\d+$/)
    return m ? parseInt(m[0], 10) : 0
  } catch {
    return 0
  }
}

function defaultScreenInfo(screenIndex: number): ScreenInfo {
  return {
    screenIndex,
    monitorName: null,
    screenSize: { width: 0, height: 0 } as PhysicalSize,
    workArea: {
      position: { x: 0, y: 0 } as PhysicalPosition,
      size: { width: 0, height: 0 } as PhysicalSize,
    },
    scaleFactor: 1,
    isPrimary: screenIndex === 0,
    hasNotch: false,
    aerospace: null,
  }
}

async function fetchAeroSpaceMonitors(): Promise<AeroSpaceMonitorInfo[]> {
  const result = await Command.create('exec-sh', [
    '-c',
    '/opt/homebrew/bin/aerospace list-monitors --json',
  ]).execute()
  const raw = JSON.parse(result.stdout) as Array<{
    'monitor-id': number
    'monitor-name': string
  }>
  return raw.map((m) => ({ monitorId: m['monitor-id'], monitorName: m['monitor-name'] }))
}

async function buildScreenInfo(): Promise<ScreenInfo> {
  const screenIndex = getScreenIndex()

  const [monitor, primary] = await Promise.all([currentMonitor(), primaryMonitor()])

  if (!monitor) return defaultScreenInfo(screenIndex)

  const isPrimary = !!primary && monitor.name === primary.name
  // Notched MacBook Pros have a taller menu bar (≈38pt vs normal 24pt)
  const menuBarHeight = monitor.workArea.position.y / monitor.scaleFactor
  const hasNotch = menuBarHeight > 30

  let aerospace: AeroSpaceMonitorInfo | null = null
  try {
    // AeroSpace assigns monitor-id by left-to-right physical position, 1-based
    const allMonitors = await availableMonitors()
    const sorted = [...allMonitors].sort((a, b) => a.position.x - b.position.x)
    const rank = sorted.findIndex(
      (m) => m.position.x === monitor.position.x && m.position.y === monitor.position.y
    )
    if (rank !== -1) {
      const monitorId = rank + 1
      const asList = await fetchAeroSpaceMonitors()
      aerospace = asList.find((a) => a.monitorId === monitorId) ?? null
    }
  } catch {
    // AeroSpace not running or not installed — silently skip
  }

  return {
    screenIndex,
    monitorName: monitor.name,
    screenSize: monitor.size,
    workArea: monitor.workArea,
    scaleFactor: monitor.scaleFactor,
    isPrimary,
    hasNotch,
    aerospace,
  }
}

const ScreenContext = createContext<ScreenInfo>(defaultScreenInfo(0))

export function ScreenProvider({ children }: { children: React.ReactNode }) {
  const [info, setInfo] = useState<ScreenInfo>(() => defaultScreenInfo(getScreenIndex()))

  useEffect(() => {
    buildScreenInfo().then(setInfo).catch(console.error)
  }, [])

  return <ScreenContext.Provider value={info}>{children}</ScreenContext.Provider>
}

export function useScreen(): ScreenInfo {
  return useContext(ScreenContext)
}
