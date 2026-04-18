import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import { ScreenProvider } from './context/ScreenContext'

const DevMain = React.lazy(() => import('./dev/DevMain').then(module => ({ default: module.DevMain })))

// Check if running in Tauri or normal browser
const isTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window


if (isTauri) {
  ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
    <React.StrictMode>
      <ScreenProvider>
        <App />
      </ScreenProvider>
    </React.StrictMode>
  )
} else {
  ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
    <React.StrictMode>
      <DevMain />
    </React.StrictMode>
  )
}