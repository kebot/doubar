import { useEffect } from 'react'
import { Pill } from '../../components/Bar'
import { useSpotifyStore } from './store'

export default function Spotify() {
  const { track, artist, artworkUrl, isPlaying, fetch } = useSpotifyStore()

  useEffect(() => {
    fetch()
    const id = setInterval(fetch, 2000)
    return () => clearInterval(id)
  }, [fetch])

  if (!isPlaying || !track) return null

  return (
    <Pill className="bg-background gap-2 px-1">
      {artworkUrl && (
        <img src={artworkUrl} className="h-full aspect-square rounded-full object-cover" />
      )}
      <span className="pr-3">▶ {artist} – {track}</span>
    </Pill>
  )
}
