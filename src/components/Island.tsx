import { useEffect, useRef, useState } from 'react'
import { invoke } from '@tauri-apps/api/core'
import { useOnClickOutside } from 'usehooks-ts'
import clsx from 'clsx'

interface NotchSize {
  width: number
  height: number
  top_inset: number
}

const getNotchSize = async () => {
  return await invoke<NotchSize>('get_notch_size')
}

export const Island = ({
  children
}: {
  children: React.ReactNode
}) => {
  const [notchSize, setNotchSize] = useState<NotchSize | null>(null)
  const [show, setShow] = useState(false)

  useEffect(() => {
    getNotchSize().then((notch) => {
      setNotchSize(notch)
    })
  }, [])

  useEffect(() => {
    invoke('get_now_playing_info').then((media) => {
      console.log(media)
    })
  }, [])

  useEffect(() => {
    if (show) {
      invoke('set_window_behavior', {
        alwaysOnTop: true,
        alwaysOnBottom: false,
      })
    } else {
      invoke('set_window_behavior', {
        alwaysOnTop: false,
        alwaysOnBottom: true
      })
    }
  }, [show])

  const ref = useRef<HTMLDivElement>(null)
  useOnClickOutside(ref as any, () => setShow(false))

  return (
    <div ref={ref}
      onClick={() => setShow(!show)}
      className={clsx(
        'absolute text-foreground rounded-3xl p-2', show ? 'bg-[#000]' : 'bg-background/50',
        'transition-all duration-300',
      )}

      style={{
        width: show ? (notchSize?.width || 0) + 100 : notchSize?.width,
        height: show ? (notchSize?.height || 0) + 32 : notchSize?.height,
        top: 0,
        left: '50%',
        transform: 'translateX(-50%)',
      }}
    >
      <div className='absolute bottom-0 text-foreground rounded-lg p-2'>
        {children}
      </div>
    </div>
  )
}
