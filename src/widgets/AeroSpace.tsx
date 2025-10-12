import { Command } from '@tauri-apps/plugin-shell'
import { useState, useEffect } from 'react'
import clsx from 'clsx'
import { AppIcon } from '../components/AppIcon'
// import { create } from 'zustand'

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
  )}>{id}  <span>&nbsp;</span> {windows.map((window) =>
    <AppIcon
      key={window["window-id"]}
      appName={window["app-name"]}
      className={clsx('mr-2', 'w-4', 'h-4', isFocused ? '' : 'contrast-50')}
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
