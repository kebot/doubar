import { Command } from '@tauri-apps/plugin-shell'
import { useState, useEffect } from 'react'

async function getFocusedWorkspace() {
  try {
    let result = await Command.create('exec-sh', [
      '-c',
      '/opt/homebrew/bin/aerospace list-workspaces --focused',
    ]).execute()

    return result.stdout
  } catch (error) {
    console.error(error)
    return 'None'
  }
}

export default function AeroSpace() {
  const [focusedWorkspace, setFocusedWorkspace] = useState('not set')

  useEffect(() => {
    getFocusedWorkspace().then((workspace) => {
      setFocusedWorkspace(workspace)
    })
  }, [])

  return <span> | Current Workspace: {focusedWorkspace}</span>
}
