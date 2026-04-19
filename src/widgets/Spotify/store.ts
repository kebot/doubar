import { create } from 'zustand'
import { Command } from '@tauri-apps/plugin-shell'

interface SpotifyStore {
  track: string | null
  artist: string | null
  artworkUrl: string | null
  isPlaying: boolean
  fetch: () => Promise<void>
}

const CMD =
  `osascript -e 'tell application "Spotify" to if player state is playing then ` +
  `return (artist of current track) & "|||" & (name of current track) & "|||" & (artwork url of current track)'`

export const useSpotifyStore = create<SpotifyStore>((set) => ({
  track: null,
  artist: null,
  artworkUrl: null,
  isPlaying: false,
  fetch: async () => {
    try {
      const result = await Command.create('exec-sh', ['-c', CMD]).execute()
      const raw = result.stdout.trim()
      if (!raw) {
        set({ isPlaying: false })
        return
      }
      const [artist, track, artworkUrl] = raw.split('|||')
      set({ isPlaying: true, artist: artist ?? null, track: track ?? null, artworkUrl: artworkUrl ?? null })
    } catch {
      set({ isPlaying: false })
    }
  },
}))
