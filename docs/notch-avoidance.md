# MacBook Pro Notch Avoidance Implementation

## Overview

This implementation detects the MacBook Pro notch and adjusts the bar layout to leave a gap in the center, ensuring content doesn't get blocked by the physical notch.

## How It Works

### Backend (Rust/Tauri)

**File:** `src-tauri/src/commands/get_safe_area_insets.rs`

The backend uses macOS APIs to detect the notch through `NSScreen`'s auxiliary areas:

- `auxiliaryTopLeftArea`: The area to the left of the notch
- `auxiliaryTopRightArea`: The area to the right of the notch

The command calculates:
- **Notch width**: `screen_width - left_area_width - right_area_width`
- **Notch height**: The maximum height of the auxiliary areas
- **Has notch**: Whether either auxiliary area has width > 0

This approach is accurate and automatically handles:
- MacBooks without a notch (returns 0 width)
- External monitors (no auxiliary areas)
- Different screen configurations

### Frontend (React/TypeScript)

#### 1. Bar Component (`src/components/Bar.tsx`)

The Bar uses a three-column CSS Grid when a notch gap is present:

- With notch: `grid-template-columns: 1fr [notchWidth] 1fr`
  - Left column: `leftOfNotch`
  - Middle column: empty notch gap
  - Right column: flex container rendering `rightOfNotch` (left-aligned) and `right` (far right)

- Without notch: falls back to the original flex layout with `justify-between`.

Props:
- `leftOfNotch`: JSX for the left side of the notch
- `rightOfNotch`: JSX for the right side of the notch (left-aligned inside right column)
- `center`: `{ width: number }` to reserve the notch gap
- `right`: JSX rendered at the far right (e.g., time widget)

#### 2. AeroSpace Component (`src/widgets/AeroSpace.tsx`)

Enhanced to support automatic splitting by available width:

Props used for splitting:
- `autoSplitSide: 'left' | 'right'`: Enables auto-splitting; component renders its half based on capacity.
- `screenWidth?: number`: Full screen width (from backend).
- `notchWidth?: number`: Reserved notch width (from backend + padding).
- `reservedRightWidth?: number`: Measured width reserved for the `right` content (time widget) on the far right.

Algorithm:
- Compute total content width: `screenWidth - notchWidth`.
- Left capacity: half of total content width.
- Right capacity: half of total content width minus `reservedRightWidth`.
- Split ratio: `leftCapacity / (leftCapacity + rightCapacity)`.
- Split index: `round(totalWorkspaces * splitRatio)`.

Notes:
- The component still supports `maxWorkspaces` and `startIndex`, but the app now uses `autoSplitSide` with capacity-based splitting.

#### 3. App Component (`src/App.tsx`)

On mount, the App:
1. Calls `get_safe_area_insets()` and stores `screenWidth` and `notchWidth` (with +40px padding).
2. Measures the width of the time widget periodically and stores it as `reservedRightWidth`.
3. Renders:
   - With notch: two `AeroSpace` instances with `autoSplitSide='left'` and `'right'`, passing `screenWidth`, `notchWidth`, and `reservedRightWidth` to both, plus `center={{ width: notchWidth }}` on the Bar.
   - Without notch: original single `AeroSpace` with `right` time widget.

## Visual Result

### With Notch (Split Workspaces Layout)
```
┌─────────────────────────────────────────────────┐
│ [Left by width]   ▓▓▓   [Right by width] [Time] │
│                  NOTCH                          │
└─────────────────────────────────────────────────┘
  1fr              gap           1fr (flex: left + far-right)
```

The layout intelligently splits workspaces by available width, reserving space for the time widget on the far right.

### Without Notch
```
┌─────────────────────────────────────────────────┐
│ [All Workspace Icons]          [Time Widget]    │
└─────────────────────────────────────────────────┘
```

## Benefits

1. ✅ **Accurate Detection**: Uses official macOS APIs for precise notch dimensions
2. ✅ **Automatic Adaptation**: Works on MacBooks with and without notches
3. ✅ **External Monitor Support**: Defaults to regular layout when no notch
4. ✅ **Flexible Layout**: CSS Grid allows precise control over spacing
5. ✅ **Future-Proof**: Easy to adjust padding or add center content

## Testing

To test the implementation:

1. **On MacBook Pro with notch**: 
   - Run the app and verify a gap appears in the center
   - Check console for notch info logs
   
2. **On MacBook without notch**:
   - Should show original layout with no gap
   
3. **On external monitor**:
   - Should show original layout with no gap

## Configuration

### Adjust Notch Padding

To adjust the padding around the notch, modify this line in `App.tsx`:

```typescript
// Add more or less padding (currently 40px = 20px each side)
setNotchWidth(info.notch_width + 40)
```

### Customize Workspace Split Behavior

You can bias the split left/right by adjusting:
- The padding applied to `notchWidth` (+40px by default)
- The breathing room added to the measured time widget width (+16px by default)

If you prefer fixed counts instead of auto width-based splitting, you can still use `maxWorkspaces` and `startIndex` props on `AeroSpace` (not used by default).

## Future Enhancements

Possible improvements:
- Dynamic padding based on content width
- Option to show something useful in the notch gap (e.g., centered time)
- Responsive adjustments for different screen sizes
- Animation when transitioning between layouts

