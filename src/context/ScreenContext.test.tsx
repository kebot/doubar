import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, act } from '@testing-library/react'
import { ScreenProvider, useScreen } from './ScreenContext'

// Tauri APIs are unavailable in jsdom — mock them
vi.mock('@tauri-apps/api/window', () => ({
  getCurrentWindow: () => ({ label: 'bar_1' }),
  currentMonitor: vi.fn(),
  primaryMonitor: vi.fn(),
}))

vi.mock('@tauri-apps/plugin-shell', () => ({
  Command: {
    create: () => ({
      execute: vi.fn().mockResolvedValue({ stdout: '[]' }),
    }),
  },
}))

import { currentMonitor, primaryMonitor } from '@tauri-apps/api/window'

const mockMonitor = {
  name: 'LG HDR 4K',
  size: { width: 3840, height: 2160 },
  workArea: { position: { x: 0, y: 48 }, size: { width: 3840, height: 2112 } },
  scaleFactor: 2,
}

function ScreenDebug() {
  const info = useScreen()
  return (
    <div>
      <span data-testid="index">{info.screenIndex}</span>
      <span data-testid="name">{info.monitorName}</span>
      <span data-testid="primary">{String(info.isPrimary)}</span>
      <span data-testid="notch">{String(info.hasNotch)}</span>
    </div>
  )
}

describe('ScreenContext', () => {
  beforeEach(() => {
    vi.mocked(currentMonitor).mockResolvedValue(mockMonitor as never)
    vi.mocked(primaryMonitor).mockResolvedValue({ ...mockMonitor, name: 'Built-in' } as never)
  })

  it('parses screen index from window label', async () => {
    await act(async () => {
      render(<ScreenProvider><ScreenDebug /></ScreenProvider>)
    })
    expect(screen.getByTestId('index').textContent).toBe('1')
  })

  it('populates monitor name from currentMonitor()', async () => {
    await act(async () => {
      render(<ScreenProvider><ScreenDebug /></ScreenProvider>)
    })
    expect(screen.getByTestId('name').textContent).toBe('LG HDR 4K')
  })

  it('isPrimary false when names differ', async () => {
    await act(async () => {
      render(<ScreenProvider><ScreenDebug /></ScreenProvider>)
    })
    expect(screen.getByTestId('primary').textContent).toBe('false')
  })

  it('hasNotch false when menu bar height ≤ 30pt', async () => {
    // workArea.position.y=48, scaleFactor=2 → 24pt ≤ 30 → no notch
    await act(async () => {
      render(<ScreenProvider><ScreenDebug /></ScreenProvider>)
    })
    expect(screen.getByTestId('notch').textContent).toBe('false')
  })

  it('hasNotch true when menu bar height > 30pt', async () => {
    vi.mocked(currentMonitor).mockResolvedValue({
      ...mockMonitor,
      workArea: { position: { x: 0, y: 76 }, size: mockMonitor.workArea.size },
    } as never)
    await act(async () => {
      render(<ScreenProvider><ScreenDebug /></ScreenProvider>)
    })
    expect(screen.getByTestId('notch').textContent).toBe('true')
  })
})
