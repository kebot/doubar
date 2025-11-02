import { Command } from '@tauri-apps/plugin-shell'
import { useEffect, useState } from 'react'
import { useInterval } from 'usehooks-ts'

type SpotifyTrack = {
  name: string
  artist: string
  album: string
  artworkUrl: string
  duration: number
  id: string
}

type SpotifyState = {
  isRunning: boolean
  playerState: 'stopped' | 'playing' | 'paused'
  currentTrack: SpotifyTrack | null
  playerPosition: number
  soundVolume: number
  repeating: boolean
  shuffling: boolean
}

export async function executeAppleScript(script: string): Promise<string> {
  try {
    // Split script into lines and create -e flag for each non-empty line
    const lines = script
      .split('\n')
      .map(line => line.trim())
      .filter(line => line.length > 0)

    const args = lines.flatMap(line => ['-e', line])

    const result = await Command.create('osascript', args).execute()
    return result.stdout.trim()
  } catch (error) {
    console.error('AppleScript error:', error)
    return ''
  }
}

export async function getSpotifyState(): Promise<SpotifyState> {
  const isRunningScript = `
    tell application "System Events"
      return (name of processes) contains "Spotify"
    end tell
  `
  const isRunning = (await executeAppleScript(isRunningScript)) === 'true'

  if (!isRunning) {
    return {
      isRunning: false,
      playerState: 'stopped',
      currentTrack: null,
      playerPosition: 0,
      soundVolume: 0,
      repeating: false,
      shuffling: false,
    }
  }

  const stateScript = `
    tell application "Spotify"
      set trackName to ""
      set trackArtist to ""
      set trackAlbum to ""
      set trackArtworkUrl to ""
      set trackDuration to 0
      set trackId to ""
      set pState to "stopped"
      set pPosition to 0
      set vol to 0
      set rep to false
      set shuf to false

      if player state is not stopped then
        set trackName to name of current track
        set trackArtist to artist of current track
        set trackAlbum to album of current track
        set trackArtworkUrl to artwork url of current track
        set trackDuration to duration of current track
        set trackId to id of current track
      end if

      set pState to player state as string
      set pPosition to player position
      set vol to sound volume
      set rep to repeating
      set shuf to shuffling

      return trackName & "|" & trackArtist & "|" & trackAlbum & "|" & trackArtworkUrl & "|" & trackDuration & "|" & trackId & "|" & pState & "|" & pPosition & "|" & vol & "|" & rep & "|" & shuf
    end tell
  `

  const result = await executeAppleScript(stateScript)
  const [name, artist, album, artworkUrl, duration, id, playerState, playerPosition, soundVolume, repeating, shuffling] = result.split('|')

  return {
    isRunning: true,
    playerState: playerState as 'stopped' | 'playing' | 'paused',
    currentTrack: name ? {
      name,
      artist,
      album,
      artworkUrl,
      duration: parseInt(duration) || 0,
      id,
    } : null,
    playerPosition: parseFloat(playerPosition) || 0,
    soundVolume: parseInt(soundVolume) || 0,
    repeating: repeating === 'true',
    shuffling: shuffling === 'true',
  }
}

export async function spotifyCommand(command: string): Promise<void> {
  await executeAppleScript(`tell application "Spotify" to ${command}`)
}

export function useSpotifyState(): SpotifyState | null {
  const [state, setState] = useState<SpotifyState | null>(null)

  useInterval(() => {
    getSpotifyState().then(setState)
  }, 1000)

  return state
}