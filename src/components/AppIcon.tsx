import { invoke } from '@tauri-apps/api/core'
import { useState, useEffect } from 'react'
import { create } from 'zustand'

// Icon cache store
const useIconCache = create<{
  icons: Record<string, string>
  setIcon: (appName: string, iconData: string) => void
}>((set) => ({
  icons: {},
  setIcon: (appName, iconData) =>
    set((state) => ({
      icons: { ...state.icons, [appName]: iconData }
    }))
}))

export function AppIcon({ 
    appName, className = ''
}: { appName: string, className: string }) {
  const { icons, setIcon } = useIconCache()
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    // If we already have the icon, don't fetch again
    if (icons[appName]) {
      return
    }

    // Fetch the icon
    setLoading(true)
    invoke<string>('get_app_icon', { appName })
      .then((iconData) => {
        setIcon(appName, iconData)
        setLoading(false)
      })
      .catch((error) => {
        console.error(`Failed to fetch icon for ${appName}:`, error)
        setLoading(false)
      })
  }, [appName, icons, setIcon])

  const iconData = icons[appName]

  if (loading || !iconData) {
    // Fallback to text while loading or if icon fetch failed
    return (
      <span className={className}>
        {appName}
      </span>
    )
  }

  return (
    <img
      src={iconData}
      alt={appName}
      title={appName}
      className={className}
    />
  )
}
