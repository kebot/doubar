// in some cases, the UI can be placed outside of the bar
import { invoke } from '@tauri-apps/api/core'
import { Popover as BasePopover } from '@base-ui-components/react/popover'
import clsx from 'clsx'

export const Popover = ({
  children,
  trigger,
  interactable = true,
}: {
  children: React.ReactNode
  trigger: React.ReactNode
  interactable?: boolean
}) => {
  return (
    <BasePopover.Root
      onOpenChange={(open) => {
        if (!interactable) {
          return
        }

        // BUG with AeroSpace if you switch workspace during focusable=true, the window will be focusable forever
        if (open) {
          invoke('set_window_behavior', {
            ignoreCursorEvents: false,
            alwaysOnTop: true,
            alwaysOnBottom: false,
            focusable: true,
          })
        } else {
          invoke('set_window_behavior', {
            ignoreCursorEvents: false,
            alwaysOnTop: false,
            alwaysOnBottom: true,
            focusable: false,
            recreate: true,
          })
        }
      }}
    >
      <BasePopover.Trigger>{trigger}</BasePopover.Trigger>

      <BasePopover.Portal>
        <BasePopover.Positioner sideOffset={8}>
          <BasePopover.Popup className={clsx(
            'bg-transparent',
            'rounded-md',
            'p-2',
            'border-0',
            'border-foreground/20',
            'text-foreground',
          )}>
            {children}
          </BasePopover.Popup>
        </BasePopover.Positioner>
      </BasePopover.Portal>
    </BasePopover.Root>
  )
}
