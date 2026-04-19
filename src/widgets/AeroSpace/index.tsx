import { useEffect, useRef } from 'react'
import clsx from 'clsx'
import { listen } from '@tauri-apps/api/event'
import { AppIcon } from '../../components/AppIcon'
import { Popover } from '../../components/Popover'
import { Popover as BasePopover } from '@base-ui-components/react/popover'
import { Pill } from '../../components/Bar'
import { useAeroSpaceStore, type ASWindow } from './store'
import { useScreen } from '../../context/ScreenContext'

const EMPTY_WINDOWS: ASWindow[] = []

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

const WorkspaceLabel = ({ id, renameableWorkspace }: { id: string; renameableWorkspace: boolean }) => {
  const inputRef = useRef<HTMLInputElement>(null)
  const workspaceName = useAeroSpaceStore((state) => state.workspaceNameMap[id] || id)
  const setWorkspaceName = useAeroSpaceStore((state) => state.setWorkspaceName)

  useEffect(() => {
    const input = inputRef.current
    if (input) {
      input.focus()
    }
  }, [inputRef])

  const handleRename = () => {
    const input = inputRef.current

    if (input) {
      setWorkspaceName(id, input.value)
    }
  }

  if (!renameableWorkspace) {
    return <>{workspaceName}</>
  }

  return (
    <Popover trigger={<>{workspaceName}</>}>
      <div className='text-foreground'>
        <input
          type='text'
          autoCorrect='off'
          autoCapitalize='off'
          autoComplete='off'
          className='text-foreground rounded-full px-2 border-1 cursor-text outline-none backdrop-blur-xs'
          ref={inputRef}
          defaultValue={workspaceName}
        />
        <BasePopover.Close className='text-foreground rounded-full px-2 border-1 cursor-pointer outline-none backdrop-blur-xs ml-2' onClick={handleRename}>
          Rename
        </BasePopover.Close>
      </div>
    </Popover>
  )
}

function Workspace({ id, isFocused, renameableWorkspace }: { id: string; isFocused: boolean; renameableWorkspace: boolean }) {
  const windows = useAeroSpaceStore((state) => state.windowsMap[id] || EMPTY_WINDOWS)

  const hasWindows = windows.length > 0

  // only show space if there's window
  if (!hasWindows) {
    return null
  }

  return (
    <Pill className={clsx('bg-background', isFocused ? 'opacity-100' : 'opacity-80')}>
      <WorkspaceLabel id={id} renameableWorkspace={renameableWorkspace} />
      <Windows windows={windows} isFocused={isFocused} />
    </Pill>
  )
}

// order the workspace by the order of the keyboard
const workspaceOrder = (a: string) => [
  '1', '2', '3', '4', '5', '6', '7', '8', '9', '0',
  'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', '\\',
  'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'',
  'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/',
].indexOf(a.toLowerCase())

export default function AeroSpace({ renameableWorkspace }: { renameableWorkspace: boolean }) {
  const screen = useScreen()
  const focusedWorkspace = useAeroSpaceStore((state) => state.focusedWorkspace)
  const workspaces = useAeroSpaceStore((state) => state.workspaces)
  const fetchWorkspaces = useAeroSpaceStore((state) => state.fetchWorkspaces)

  useEffect(() => {
    const monitorId = screen.aerospace?.monitorId || 0

    // initial fetch
    fetchWorkspaces(monitorId)

    // Poll as fallback (catches changes AeroSpace doesn't emit)
    const interval = setInterval(() => fetchWorkspaces(monitorId), 10_000)

    // Immediate refresh on AeroSpace focus/workspace events
    const unlisten = listen<Record<string, string>>('aerospace', () => {
      fetchWorkspaces(monitorId)
    })

    return () => {
      clearInterval(interval)
      unlisten.then((fn) => fn())
    }
  }, [fetchWorkspaces, screen.aerospace?.monitorId])

  return (
    <div className='flex items-center gap-1'>
      {workspaces
        // sort the workspaces by the order of the keyboard
        .sort((a, b) =>
          workspaceOrder(a.workspace) - workspaceOrder(b.workspace)
        )
        .map((workspace) => {
          const isFocused = workspace.workspace === focusedWorkspace
          return (
            <Workspace key={workspace.workspace} id={workspace.workspace} isFocused={isFocused} renameableWorkspace={renameableWorkspace} />
          )
        })}
    </div>
  )
}
