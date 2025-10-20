import clsx from 'clsx'

export const Bar = ({
  className,
  left,
  center,
  right,
  leftOfNotch,
  rightOfNotch,
}: {
  className?: string
  left?: React.ReactNode
  center?: { width: number } | React.ReactNode
  right?: React.ReactNode
  leftOfNotch?: React.ReactNode
  rightOfNotch?: React.ReactNode
}) => {
  // If center is provided as an object with width, use that for the notch gap
  const notchWidth = 
    center && typeof center === 'object' && 'width' in center 
      ? center.width 
      : 0
  

  // If we have a notch width, use CSS Grid for three-column layout
  // with optional leftOfNotch and rightOfNotch content
  if (notchWidth > 0) {
    return (
      <div
        className={clsx(
          'h-[var(--bar-height)]',
          'px-2 mt-[6px]',
          'grid items-center',
          className
        )}
        style={{
          gridTemplateColumns: `1fr ${notchWidth}px 1fr`,
        }}
      >
        {/* Left of notch */}
        <div className="flex justify-start">
          {leftOfNotch || left}
        </div>
        
        {/* Empty space for notch */}
        <div />
        
        {/* Right of notch - can contain multiple items */}
        <div className="flex justify-between items-center gap-1">
          {rightOfNotch && <div className="flex justify-start">{rightOfNotch}</div>}
          {right && <div className="flex justify-end ml-auto">{right}</div>}
        </div>
      </div>
    )
  }

  // Original layout without notch
  return (
    <div
      className={clsx(
        'h-[var(--bar-height)]',
        'px-2 mt-[6px]',
        'flex items-center justify-between gap-1',
        className
      )}
    >
      {left && <div>{left}</div>}
      {center && typeof center !== 'object' && <div>{center}</div>}
      {right && <div>{right}</div>}
    </div>
  )
}

export const Pill = ({
  children,
  className,
}: {
  children: React.ReactNode
  className?: string
}) => {
  return (
    <div
      className={clsx(
        'text-foreground',
        'h-[var(--bar-height)]',
        'px-4',
        'rounded-full',
        'flex items-center',
        'backdrop-blur-sm',
        'outline-0 shadow-none',
        'transition-all duration-300',
        className || 'bg-background'
      )}
    >
      {children}
    </div>
  )
}
