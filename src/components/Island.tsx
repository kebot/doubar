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

  return <div className={clsx(
    'fixed', 'top-[4px]', 'left-[25%]', 'w-0', 'overflow-visible',
    'text-foreground'
  )}>

    <div className='whitespace-nowrap'>hello world</div>
  </div>

  // return (
  //   <div
  //     ref={ref}
  //     onClick={() => setShow(!show)}
  //     className={clsx(
  //       'absolute text-foreground rounded-3xl p-2', show ? 'bg-[#000]' : 'bg-background/50',
  //       'transition-all duration-300',
  //       'overflow-hidden',
  //     )}

  //     style={{
  //       minWidth: show ? (notchSize?.width || 0) + 100 : notchSize?.width,
  //       height: show ? (notchSize?.height || 0) + 32 : notchSize?.height,
  //       top: 4,
  //       left: '50%',
  //       transform: 'translateX(-50%)',
  //     }}
  //   >
  //     {!show && <div>
  //       <div 
  //         className='inline-block'
  //         style={{
  //           width: notchSize?.width || 0,
  //         }}
  //       />
  //     </div>}
  //   </div>
  // )
}
