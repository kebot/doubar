import clsx from 'clsx'

export const Bar = ({
  className,
  left,
  right,
}: {
  className?: string
  left?: React.ReactNode
  right?: React.ReactNode
}) => {
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
