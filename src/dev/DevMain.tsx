// import clsx from 'clsx'
import { Bar, Pill } from '../components/Bar'
import { TimeWidget } from '../widgets/Time'

// mock
;(window as any).__TAURI_INTERNALS__ = {
  invoke: async (cmd: string, args: any) => {
    console.log('invoke', cmd, args)
    return 'mock'
  },
}

// IDEA: using vanilla-extract to build the UI: https://vanilla-extract.style/
export function DevMain() {
  return (
    <div
      className='text-foreground h-screen font-sans py-4 px-4 bg-no-repeat bg-cover bg-center'
      style={{
        backgroundImage: 'url(https://picsum.photos/1920/1080)',
      }}
    >
      <Bar
        left={
          <div className='flex items-center gap-1'>
            <Pill>normal</Pill>
            <Pill className='bg-background/10'>active</Pill>
            <Pill className='bg-black'>black</Pill>
            <Pill className='bg-red'>red</Pill>
            <Pill className='bg-blue'>green</Pill>
            <Pill className='bg-yellow'>yellow</Pill>
            <Pill className='bg-green'>blue</Pill>
            <Pill className='bg-magenta'>magenta</Pill>
            <Pill className='bg-cyan'>cyan</Pill>
            <Pill className='bg-white'>white</Pill>
          </div>
        }
        right={<TimeWidget />}
      />
    </div>
  )
}
