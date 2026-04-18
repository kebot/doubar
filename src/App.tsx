import './App.css'
import AeroSpace from './widgets/AeroSpace'
import { TimeWidget } from './widgets/Time'
import { Bar } from './components/Bar'

function App() {
  return (
    <main className='w-full h-[100vh]'>
      <Bar left={<AeroSpace renameableWorkspace={false} />} right={<TimeWidget />} />
    </main>
  )
}

export default App
