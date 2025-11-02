import { Island } from '../components/Island'
import { useSpotifyState } from '../lib/spotify'

function formatTime(seconds: number): string {
  const mins = Math.floor(seconds / 60)
  const secs = Math.floor(seconds % 60)
  return `${mins}:${secs.toString().padStart(2, '0')}`
}

export function SpotifyWidget() {
  const state = useSpotifyState()

  if (!state) {
    return null
  }

  return <Island>
    {state.currentTrack?.name}
  </Island>
}
