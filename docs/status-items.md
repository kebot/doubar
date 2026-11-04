## Status items

Doubar replaces the macOS menu bar, but the items in it (Stats, magpie, Wi-Fi,
the battery) still belong to other apps. Doubar can't move them into its own
bar. It draws pictures of them, and when you click a picture it asks the real
item to open, then moves what opens under the pill you clicked. The code is in
`Widgets/StatusItems.swift`.

### Finding the items

- macOS keeps drawing the system menu bar even while it is auto-hidden.
  `MenuBarAgent` draws the whole bar into one window.
- Accessibility lists a button for every item in that window. Each button says
  which app owns it and where it sits horizontally. Doubar reads that list.
- ScreenCaptureKit captures the same window. Doubar cuts out one picture per
  item, using the positions from Accessibility.
- Both permissions are needed. Without Screen Recording there are no pictures;
  without Accessibility there is nothing to click.

### Naming an item

A layout entry such as `status:eu.exelban.Stats/RAM: Pie chart` has to keep
matching the same item between launches. The name comes from the item's
identifier, description, title or tooltip, whichever it has.

Only the first line of that text is used. magpie, for example, puts today's
token count on the lines below its name, and those change all the time. If the
whole text were the name, its entry would stop matching and the item would
disappear from the bar. Entries saved with the whole text still match by their
first line.

### Why a click needs its own window

Doubar's bar sits at the bottom of the window stack, under every app window. As
soon as the pointer reaches the top edge, macOS slides its own menu bar over it
and takes the click, so a click on a pill never arrived.

Each mirrored item therefore also gets a small transparent panel that draws the
same picture and sits above the system menu bar. That panel receives the click.
It never activates doubar, so the app you were using stays frontmost. Right-click
opens doubar's own menu for the item, not the app's.

### What a click does

1. The panel passes the click to `StatusItems.press`, together with where the
   pill is on screen.
2. Doubar looks the item up again, in that app only. The button it kept from
   earlier can accept a press and do nothing after you move to another display,
   so it needs a current one.
3. Doubar starts listening for that app creating a window, then presses the
   real item through Accessibility (`AXPress`). The press runs on its own
   thread because it can wait until the popup closes.
4. The app opens its popup where its item really is, in the hidden menu bar.
   Briefly you can see it there.
5. Accessibility tells doubar a window was created, and doubar moves it.

### Where the popup goes

The popup is centred under the pill, kept 8 pt inside the display, and placed
6 pt below the pill. Accessibility measures from the top-left of the primary
display, so the position is converted before it is set.

A short poll, every 4 ms, runs alongside the notification. Some apps reuse one
window instead of creating a new one, and for those the notification never
comes.

Spotlight's item ignores `AXPress`. For it doubar presses your Spotlight
keyboard shortcut instead.

### What can go wrong

- The popup can show at its original position for about one frame before it
  moves. The app chooses where its window first appears, and doubar can only
  move it afterwards.
- Real menus (`NSMenu`) aren't windows that Accessibility can move. They open
  under the hidden item.
- On a narrow display such as a MacBook's, macOS piles the items that don't fit
  behind its overflow chevron. Doubar can't capture those, so it keeps the last
  good picture and width. If it never had one, as after a restart while the
  narrow display is the active one, the item is missing until the active menu
  bar is a wide display. Pointing at the top edge of the wide display is enough.
- Clicks on the system menu bar's own items, not mirrored ones, are untouched.

`doubar emit status-item id=<id>` presses an item without a click. It opens the
popup where the app puts it, since there is no pill to place it under.
