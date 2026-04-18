import './App.css'
import AeroSpace from './widgets/AeroSpace'
import { TimeWidget } from './widgets/Time'
import { ClaudeUsageWidget } from './widgets/ClaudeUsage'
import { Bar } from './components/Bar'

function App() {
  return (
    <main className='w-full h-[100vh]'>
      <Bar
        left={<AeroSpace renameableWorkspace={false} />}
        right={
          <div className='flex items-center gap-1'>
            <ClaudeUsageWidget />
            <TimeWidget />
          </div>
        }
      />
    </main>
  )
}

export default App
