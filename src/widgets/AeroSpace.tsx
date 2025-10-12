import { Command } from '@tauri-apps/plugin-shell'
import { invoke } from '@tauri-apps/api/core'
import { useState, useEffect } from 'react'
import clsx from 'clsx'
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

type ASWorkspace = { workspace: string };

type ASWindow = {
  "app-name": string,
  "window-id": number,
  "window-title": string
}

type ASMonitor = {
  "monitor-id": number,
  "monitor-name": string
}

type ASApp = {
  "app-bundle-0id": string,
  "app-name": string,
  "app-pid": number
}

async function aeroSpaceQuery<T>(query: string): Promise<T> {
  let result = await Command.create('exec-sh', [
    '-c',
    `/opt/homebrew/bin/aerospace ${query} --json`,
  ]).execute()

  return JSON.parse(result.stdout) as T
}

function useWorkspaces(): [string, ASWorkspace[]] {
  const [focusedWorkspace, setFocusedWorkspace] = useState<string>('')
  const [workspaces, setWorkspaces] = useState<ASWorkspace[]>([])

  useEffect(() => {
    const interval = setInterval(() => {
      aeroSpaceQuery<ASWorkspace[]>('list-workspaces --focused').then((workspaces) => {
        setFocusedWorkspace(workspaces[0].workspace)
      })

      aeroSpaceQuery<ASWorkspace[]>('list-workspaces --monitor 1').then((workspaces) => {
        setWorkspaces(workspaces)
      })
    }, 1000)

    return () => clearInterval(interval)
  }, [])

  return [focusedWorkspace, workspaces]
}

function AppIcon({ appName, isFocused }: { appName: string, isFocused: boolean }) {
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
      <span className={clsx('mr-2', isFocused ? 'text-foreground' : 'text-foreground/50')}>
        {appName}
      </span>
    )
  }

  return (
    <img
      src={iconData}
      alt={appName}
      title={appName}
      className="w-4 h-4 mr-2"
    />
  )
}

function Workspace({ id, isFocused }: { id: string, isFocused: boolean }) {
  const [windows, setWindows] = useState<ASWindow[]>([])

  useEffect(() => {
    const interval = setInterval(() => {
      aeroSpaceQuery<ASWindow[]>(`list-windows --workspace ${id}`).then((windows) => {
        setWindows(windows)
      })
    }, 1000)

    return () => clearInterval(interval)
  }, [id])

  const hasWindows = windows.length > 0

  // only show space if there's window
  if (!hasWindows) {
    return null
  }

  return <span className={clsx(
    'text-foreground',
    'shadow-none',
    'outline-none',
    'px-8',
    'rounded-full',
    'flex items-center',
    isFocused ? 'bg-background' : 'bg-black'
  )}>{id} / {windows.map((window) =>
    <AppIcon
      key={window["window-id"]}
      appName={window["app-name"]}
      isFocused={isFocused}
    />
  )}</span>
}

export default function AeroSpace() {
  const [focusedWorkspace, workspaces] = useWorkspaces()

  return (
    <div className="flex items-center gap-1">
      {workspaces.map((workspace) => {
        const isFocused = workspace.workspace === focusedWorkspace
        return <Workspace key={workspace.workspace} id={workspace.workspace} isFocused={isFocused} />
      })}
    </div>
  )
}
