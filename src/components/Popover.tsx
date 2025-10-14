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

        if (open) {
          invoke('set_window_behavior', {
            ignoreCursorEvents: false,
            alwaysOnTop: true,
            alwaysOnBottom: false,
          })
        } else {
          invoke('set_window_behavior', {
            ignoreCursorEvents: false,
            alwaysOnTop: false,
            alwaysOnBottom: true,
          })
        }
      }}
    >
      <BasePopover.Trigger>{trigger}</BasePopover.Trigger>

      <BasePopover.Portal>
        <BasePopover.Positioner sideOffset={8}>
          <BasePopover.Popup className={clsx(
            'bg-background/80',
            'rounded-md',
            'p-2',
            'border',
            'border-foreground/20',
            'w-48',
            'text-foreground',
          )}>
            {children}
          </BasePopover.Popup>
        </BasePopover.Positioner>
      </BasePopover.Portal>
    </BasePopover.Root>
  )
}
