import { Command } from '@tauri-apps/plugin-shell'
import { useEffect, useState } from 'react'
import clsx from 'clsx'
import { AppIcon } from '../components/AppIcon'
import { Popover } from '../components/Popover'

type ASWorkspace = { workspace: string }

type ASWindow = {
  'app-name': string
  'window-id': number
  'window-title': string
}

type ASMonitor = {
  'monitor-id': number
  'monitor-name': string
}

type ASApp = {
  'app-bundle-0id': string
  'app-name': string
  'app-pid': number
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

function Windows({ windows, isFocused }: { windows: ASWindow[]; isFocused: boolean }) {
  return (
    <div
      className={clsx(
        'ml-2 flex',
        'transition-all duration-300',
        isFocused ? 'contrast-100' : 'contrast-50'
      )}
    >
      {windows.map((window, index) => (
        <AppIcon
          key={window['window-id']}
          appName={window['app-name']}
          className={clsx(
            'mr-2',
            'w-4',
            'h-4',
            'transition-all duration-300',
            index > 0 && !isFocused && '-ml-5'
          )}
        />
      ))}
    </div>
  )
}

const workspaceNameMap = new Map()

// you can rename your workspace
workspaceNameMap.set('1', 'random')
workspaceNameMap.set('2', 'doubar')
workspaceNameMap.set('3', 'media')

function workspaceIdToName(id: string): string {
  if (workspaceNameMap.has(id)) {
    return workspaceNameMap.get(id)
  }
  return id
}

function Workspace({ id, isFocused }: { id: string; isFocused: boolean }) {
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

  return (
    <span
      className={clsx(
        'relative',
        'text-foreground',
        'shadow-none',
        'outline-none',
        'px-4',
        'rounded-full',
        'flex items-center',
        isFocused ? 'bg-background' : 'bg-black'
      )}
    >
      <Popover
        trigger={<>{workspaceIdToName(id)}</>}
      >
        <div className='text-foreground'>Popover content</div>
      </Popover>

      <Windows windows={windows} isFocused={isFocused} />
    </span>
  )
}

export default function AeroSpace() {
  const [focusedWorkspace, workspaces] = useWorkspaces()

  return (
    <div className='flex items-center gap-1'>
      {workspaces.map((workspace) => {
        const isFocused = workspace.workspace === focusedWorkspace
        return (
          <Workspace key={workspace.workspace} id={workspace.workspace} isFocused={isFocused} />
        )
      })}
    </div>
  )
}
