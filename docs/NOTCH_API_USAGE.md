# Notch Size API Usage

## Commands Available

Two new Tauri commands have been added to retrieve notch information:

### 1. `get_notch_size`

Returns the notch dimensions including an estimated width and the actual height from safe area insets.

**Response Type:**
```typescript
interface NotchSize {
  width: number;      // Estimated notch width (approximately 12% of screen width)
  height: number;     // Actual notch height from safe area insets
  top_inset: number;  // Same as height, the top safe area inset
}
```

### 2. `get_safe_area_insets`

Returns all safe area insets for the main screen.

**Response Type:**
```typescript
interface SafeAreaInsets {
  top: number;     // Top inset (includes notch height if present)
  bottom: number;  // Bottom inset
  left: number;    // Left inset
  right: number;   // Right inset
}
```

## Usage Examples

### JavaScript/TypeScript (Tauri v2)

```typescript
import { invoke } from '@tauri-apps/api/core';

// Get notch size
async function getNotchSize() {
  try {
    const notchSize = await invoke<NotchSize>('get_notch_size');
    console.log('Notch dimensions:', notchSize);
    // Example output: { width: 220.8, height: 37, top_inset: 37 }
  } catch (error) {
    console.error('Failed to get notch size:', error);
  }
}

// Get safe area insets
async function getSafeAreaInsets() {
  try {
    const insets = await invoke<SafeAreaInsets>('get_safe_area_insets');
    console.log('Safe area insets:', insets);
    // Example output: { top: 37, bottom: 0, left: 0, right: 0 }
  } catch (error) {
    console.error('Failed to get safe area insets:', error);
  }
}

// Use the notch information to position UI elements
async function positionAroundNotch() {
  const notchSize = await invoke<NotchSize>('get_notch_size');

  if (notchSize.height > 0) {
    // Device has a notch
    console.log(`Notch detected: ${notchSize.width}px wide, ${notchSize.height}px tall`);

    // Add padding to avoid the notch area
    document.documentElement.style.setProperty('--notch-height', `${notchSize.height}px`);
    document.documentElement.style.setProperty('--notch-width', `${notchSize.width}px`);
  } else {
    console.log('No notch detected');
  }
}
```

### CSS Usage

```css
:root {
  --notch-height: 0px;
  --notch-width: 0px;
}

/* Avoid content under the notch */
.top-bar {
  padding-top: var(--notch-height);
}

/* Position content to the left or right of the notch */
.left-section {
  width: calc((100vw - var(--notch-width)) / 2);
}
```

## Notes

- The notch **height** is accurate and comes directly from `NSScreen.safeAreaInsets.top`
- The notch **width** is estimated at ~12% of screen width since macOS doesn't expose the exact notch width
- For typical MacBook Pros with notches:
  - Height: ~32-37 pixels (at 2x scaling)
  - Width: ~200-230 pixels (at 2x scaling)
- On devices without a notch, all values will be 0
- These commands must be called on the main thread (Tauri handles this automatically)
