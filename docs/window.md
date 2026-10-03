## Window

- One borderless, non-activating `NSPanel` per display (`BarWindow.swift`), keyed
  by `CGDirectDisplayID` and kept in sync on
  `didChangeScreenParametersNotification` and wake.
- The panel spans the full display width, flush with the top edge, so it can
  cover the notch area. It is only as tall as the bar.
- Level is `normalWindow - 1` (always on bottom): under every app window, above
  the desktop. It joins all Spaces and takes clicks (`acceptsFirstMouse`), hover
  and scroll.
- `canHide = false` and `orderFrontRegardless()`: the app runs with the
  `.accessory` activation policy, is never active, and can start with
  `NSApp.isHidden` set depending on what launched it.
- The peek preview is a separate non-activating panel at `.popUpMenu` level,
  so it shows above app windows, placed below the hovered pill.
