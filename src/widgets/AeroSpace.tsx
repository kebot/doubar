import { Command } from '@tauri-apps/plugin-shell'
import { useEffect, useRef, useState } from 'react'
import clsx from 'clsx'
import { AppIcon } from '../components/AppIcon'
import { Popover } from '../components/Popover'
import { Popover as BasePopover } from '@base-ui-components/react/popover'
import { Pill } from '../components/Bar'

type ASWorkspace = { workspace: string }

type ASWindow = {
  'app-name': string
  'window-id': number
  'window-title': string
}

// Removed unused types for cleanliness

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

// TODO save it to persistent storage
const workspaceNameMap = new Map()

function workspaceIdToName(id: string): string {
  if (workspaceNameMap.has(id)) {
    return workspaceNameMap.get(id) || id
  }
  return id
}

const WorkspaceLabel = ({ id, renameableWorkspace }: { id: string; renameableWorkspace: boolean }) => {
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    const input = inputRef.current
    if (input) {
      input.focus()
    }
  }, [inputRef])

  const handleRename = () => {
    const input = inputRef.current

    if (input) {
      workspaceNameMap.set(id, input.value)
    }
  }

  if (!renameableWorkspace) {
    return <>{workspaceIdToName(id)}</>
  }

  return (
    <Popover trigger={<>{workspaceIdToName(id)}</>}>
      <div className='text-foreground'>
        <input
          type='text' 
          autoCorrect='off'
          autoCapitalize='off'
          autoComplete='off'
          className='text-foreground rounded-full px-2 border-1 cursor-text outline-none backdrop-blur-xs'
          ref={inputRef}
          defaultValue={workspaceIdToName(id)} 
        />
        <BasePopover.Close className='text-foreground rounded-full px-2 border-1 cursor-pointer outline-none backdrop-blur-xs ml-2' onClick={handleRename}>
          Rename
        </BasePopover.Close>
      </div>
    </Popover>
  )
}

function Workspace({ id, isFocused, renameableWorkspace, showEmpty }: { id: string; isFocused: boolean; renameableWorkspace: boolean; showEmpty?: boolean }) {
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

  return (
    <Pill className={clsx('bg-background', isFocused ? 'opacity-100' : 'opacity-80', !hasWindows && !showEmpty && 'hidden', !hasWindows && showEmpty && 'opacity-60') }>
      <WorkspaceLabel id={id} renameableWorkspace={renameableWorkspace} />
      {hasWindows && <Windows windows={windows} isFocused={isFocused} />}
    </Pill>
  )
}

export default function AeroSpace({ 
  renameableWorkspace,
  maxWorkspaces,
  startIndex = 0,
  showEmpty = false,
  autoSplitSide,
  screenWidth,
  notchWidth,
  reservedRightWidth,
}: {
  renameableWorkspace: boolean
  maxWorkspaces?: number
  startIndex?: number
  showEmpty?: boolean
  autoSplitSide?: 'left' | 'right'
  screenWidth?: number
  notchWidth?: number
  reservedRightWidth?: number
}) {
  const [focusedWorkspace, workspaces] = useWorkspaces()

  // Determine which workspaces to show
  let displayWorkspaces: ASWorkspace[]
  if (autoSplitSide) {
    const n = workspaces.length
    // Base available width excluding notch
    const totalBarContentWidth = Math.max(0, (screenWidth || 0) - (notchWidth || 0))
    const halfWidth = totalBarContentWidth > 0 ? totalBarContentWidth / 2 : 0
    // Right side loses the reserved area for the time widget
    const rightCapacity = Math.max(0, halfWidth - (reservedRightWidth || 0))
    const leftCapacity = halfWidth
    const denom = leftCapacity + rightCapacity
    const leftShare = denom > 0 ? (leftCapacity / denom) : 0.5
    const splitIndex = Math.min(n, Math.max(0, Math.round(n * leftShare)))
    displayWorkspaces = autoSplitSide === 'left' ? workspaces.slice(0, splitIndex) : workspaces.slice(splitIndex)
  } else {
    displayWorkspaces = maxWorkspaces 
      ? workspaces.slice(startIndex, startIndex + maxWorkspaces)
      : workspaces.slice(startIndex)
  }

  // dev logs removed

  return (
    <div className='flex items-center gap-1'>
      {displayWorkspaces.map((workspace) => {
        const isFocused = workspace.workspace === focusedWorkspace
        return (
          <Workspace key={workspace.workspace} id={workspace.workspace} isFocused={isFocused} renameableWorkspace={renameableWorkspace} showEmpty={showEmpty} />
        )
      })}
    </div>
  )
}
