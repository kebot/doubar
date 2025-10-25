import { create } from 'zustand'
import { Command } from '@tauri-apps/plugin-shell'

export type ASWorkspace = { workspace: string }

export type ASWindow = {
  'app-name': string
  'window-id': number
  'window-title': string
}

export type ASMonitor = {
  'monitor-id': number
  'monitor-name': string
}

export type ASApp = {
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

interface AeroSpaceStore {
  // State
  focusedWorkspace: string
  workspaces: ASWorkspace[]
  windowsMap: Record<string, ASWindow[]>
  workspaceNameMap: Record<string, string>

  // Actions
  setFocusedWorkspace: (workspace: string) => void
  setWorkspaces: (workspaces: ASWorkspace[]) => void
  setWindows: (workspaceId: string, windows: ASWindow[]) => void
  setWorkspaceName: (id: string, name: string) => void

  // Fetch methods
  fetchWorkspaces: () => Promise<void>
  fetchWindows: (workspaceId: string) => Promise<void>
}

export const useAeroSpaceStore = create<AeroSpaceStore>((set, get) => ({
  // Initial state
  focusedWorkspace: '',
  workspaces: [],
  windowsMap: {},
  workspaceNameMap: {},

  // Actions
  setFocusedWorkspace: (workspace) => set({ focusedWorkspace: workspace }),

  setWorkspaces: (workspaces) => set({ workspaces }),

  setWindows: (workspaceId, windows) =>
    set((state) => ({
      windowsMap: { ...state.windowsMap, [workspaceId]: windows },
    })),

  setWorkspaceName: (id, name) =>
    set((state) => ({
      workspaceNameMap: { ...state.workspaceNameMap, [id]: name },
    })),

  // Fetch methods
  fetchWorkspaces: async () => {
    try {
      const [focused, allWorkspaces] = await Promise.all([
        aeroSpaceQuery<ASWorkspace[]>('list-workspaces --focused'),
        aeroSpaceQuery<ASWorkspace[]>('list-workspaces --monitor 1'),
      ])

      set({
        focusedWorkspace: focused[0]?.workspace || '',
        workspaces: allWorkspaces,
      })

      // Fetch windows for all workspaces
      allWorkspaces.forEach((workspace) => {
        get().fetchWindows(workspace.workspace)
      })
    } catch (error) {
      console.error('Failed to fetch workspaces:', error)
    }
  },

  fetchWindows: async (workspaceId) => {
    try {
      const windows = await aeroSpaceQuery<ASWindow[]>(
        `list-windows --workspace ${workspaceId}`
      )
      get().setWindows(workspaceId, windows)
    } catch (error) {
      console.error(`Failed to fetch windows for workspace ${workspaceId}:`, error)
    }
  },
}))