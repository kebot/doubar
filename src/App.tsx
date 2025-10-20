import './App.css'
import { useEffect, useState } from 'react'
import { invoke } from '@tauri-apps/api/core'
import AeroSpace from './widgets/AeroSpace'
import { TimeWidget } from './widgets/Time'
import { useRef } from 'react'
import { Bar } from './components/Bar'

interface NotchInfo {
  has_notch: boolean
  notch_width: number
  notch_height: number
  screen_width: number
  screen_height: number
}

function App() {
  const [notchWidth, setNotchWidth] = useState<number>(0)
  const [hasNotch, setHasNotch] = useState<boolean>(false)
  const [screenWidth, setScreenWidth] = useState<number>(0)
  const timeRef = useRef<HTMLDivElement>(null)
  const [reservedRightWidth, setReservedRightWidth] = useState<number>(0)

  useEffect(() => {
    // Fetch notch information on mount
    invoke<NotchInfo>('get_safe_area_insets')
      .then((info) => {
        // dev log removed
        if (info.has_notch) {
          setHasNotch(true)
          // Add some padding (20px on each side) for visual breathing room
          const widthWithPadding = info.notch_width + 40
          // dev log removed
          setNotchWidth(widthWithPadding)
        }
        setScreenWidth(info.screen_width)
      })
      .catch((err) => {
        console.error('[App] Failed to get notch info:', err)
      })
  }, [])

  useEffect(() => {
    const measure = () => {
      const el = timeRef.current
      if (el) {
        const w = el.getBoundingClientRect().width + 16 // small breathing room
        setReservedRightWidth(w)
        // dev log removed
      }
    }
    measure()
    const id = setInterval(measure, 1000)
    return () => clearInterval(id)
  }, [])

  // If we have a notch, split workspaces around it
  if (hasNotch) {
    // dev log removed
    return (
      <main className='w-full h-[100vh]'>
        <Bar 
          leftOfNotch={<AeroSpace renameableWorkspace={true} autoSplitSide='left' showEmpty screenWidth={screenWidth} notchWidth={notchWidth} reservedRightWidth={reservedRightWidth} />}
          center={{ width: notchWidth }}
          rightOfNotch={<AeroSpace renameableWorkspace={true} autoSplitSide='right' showEmpty screenWidth={screenWidth} notchWidth={notchWidth} reservedRightWidth={reservedRightWidth} />}
          right={<div ref={timeRef}><TimeWidget /></div>} 
        />
      </main>
    )
  }

  // No notch - original layout
  // dev log removed
  return (
    <main className='w-full h-[100vh]'>
      <Bar 
        left={<AeroSpace renameableWorkspace={true} />} 
        right={<TimeWidget />} 
      />
    </main>
  )
}

export default App
