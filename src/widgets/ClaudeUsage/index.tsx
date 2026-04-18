import { useEffect } from 'react'
import { Pill } from '../../components/Bar'
import { useClaudeUsageStore } from './store'

function formatTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
  if (n >= 1_000) return `${Math.round(n / 1_000)}k`
  return String(n)
}

export function ClaudeUsageWidget() {
  const usage = useClaudeUsageStore((s) => s.usage)
  const fetchUsage = useClaudeUsageStore((s) => s.fetchUsage)

  useEffect(() => {
    fetchUsage()
    const id = setInterval(fetchUsage, 30_000)
    return () => clearInterval(id)
  }, [fetchUsage])

  if (!usage) return null

  const todayTotal = usage.todayInput + usage.todayOutput + usage.todayCache
  const totalAll = usage.totalInput + usage.totalOutput + usage.totalCache

  return (
    <Pill className="bg-background text-foreground text-sm tabular-nums">
      CC {formatTokens(todayTotal)}
      <span className="opacity-40 ml-1">/ {formatTokens(totalAll)}</span>
    </Pill>
  )
}
