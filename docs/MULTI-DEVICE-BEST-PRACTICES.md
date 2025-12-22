# Multi-Device Best Practices

This document outlines coding standards and best practices for developing cdev-ios across iPhone and iPad devices.

## Overview

cdev-ios uses SwiftUI's size classes to detect device type:
- **Compact** (`.compact`): iPhone in portrait, iPhone in landscape (width)
- **Regular** (`.regular`): iPad, iPhone in landscape (some models)

Always test on both iPhone and iPad simulators before committing UI changes.

## 1. Responsive Layout System

### Use ResponsiveLayout for Sizing

Never hardcode sizes with ternary expressions. Use the centralized `ResponsiveLayout` system:

```swift
// ✅ CORRECT
@Environment(\.horizontalSizeClass) private var sizeClass
private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

var body: some View {
    HStack(spacing: layout.contentSpacing) {
        Image(systemName: "star")
            .font(.system(size: layout.iconMedium))
        Text("Title")
            .font(layout.bodyFont)
    }
    .padding(.horizontal, layout.standardPadding)
}

// ❌ WRONG
.padding(.horizontal, isCompact ? 12 : 16)
.font(.system(size: isCompact ? 12 : 14))
```

### ResponsiveLayout Properties

| Category | Properties | iPhone / iPad |
|----------|------------|---------------|
| Padding | `smallPadding` | 8 / 10 |
| | `standardPadding` | 12 / 16 |
| | `largePadding` | 16 / 20 |
| Icons | `iconSmall` | 9 / 10 |
| | `iconMedium` | 12 / 14 |
| | `iconLarge` | 16 / 18 |
| Components | `buttonHeight` | 36 / 40 |
| | `indicatorSize` | 32 / 36 |

See `docs/RESPONSIVE-LAYOUT.md` for the complete reference.

## 2. Sheet Presentations

### Use `.responsiveSheet()` Modifier

Sheets should display differently on iPhone vs iPad:
- **iPhone**: Half-screen (medium) expandable to full (large)
- **iPad**: Full height (large) for more content visibility

```swift
// ✅ CORRECT - Use responsiveSheet()
.sheet(isPresented: $showSettings) {
    SettingsView()
        .responsiveSheet()
}

// ❌ WRONG - Hardcoded detents
.sheet(isPresented: $showSettings) {
    SettingsView()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}
```

### The `.responsiveSheet()` Modifier

Defined in `View+Extensions.swift`:
- iPhone: `.presentationDetents([.medium, .large])`
- iPad: `.presentationDetents([.large])`
- Always includes `.presentationDragIndicator(.visible)`

## 3. Gesture Handling

### Never Block Button Taps

SwiftUI's `.onTapGesture` on containers blocks all child button taps. This causes inconsistent behavior between devices.

```swift
// ❌ WRONG - Blocks button taps
VStack {
    Text("Header")
    Button("Action") { doSomething() }  // May not work!
}
.onTapGesture {
    dismissKeyboard()
}

// ✅ CORRECT - Use simultaneousGesture
VStack {
    Text("Header")
    Button("Action") { doSomething() }  // Works correctly
}
.simultaneousGesture(
    TapGesture().onEnded { dismissKeyboard() }
)
```

### Gesture Decision Table

| Scenario | Approach |
|----------|----------|
| Keyboard dismissal on container | `.simultaneousGesture(TapGesture())` |
| Making a display-only view tappable | `.onTapGesture` |
| Row selection in lists | `Button` with `.buttonStyle(.plain)` |
| Backdrop dismiss (modal overlay) | `.onTapGesture` (no children) |
| Expand/collapse with buttons inside | `.simultaneousGesture(TapGesture())` |

### Using `.dismissKeyboardOnTap()`

The built-in modifier uses `.simultaneousGesture` internally:

```swift
// Safe to use on any view
TabView(selection: $selectedTab) {
    // content
}
.dismissKeyboardOnTap()
```

## 4. Layout Patterns

### iPhone vs iPad Layouts

```swift
struct MyView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        if isCompact {
            // iPhone: Vertical stack
            VStack { content }
        } else {
            // iPad: Side-by-side
            HStack { content }
        }
    }
}
```

### Navigation Patterns

| Device | Pattern |
|--------|---------|
| iPhone | Push navigation, sheets for modals |
| iPad | Split view, larger sheets, inline popovers |

## 5. Testing Checklist

Before committing UI changes, test on:

- [ ] iPhone SE (smallest screen)
- [ ] iPhone 16 Pro (standard)
- [ ] iPhone 16 Pro Max (largest iPhone)
- [ ] iPad mini (smallest iPad)
- [ ] iPad Pro 13" (largest iPad)

### Key Test Scenarios

1. **Sheets**: Open all sheets, verify they display at correct height
2. **Buttons**: Tap all buttons, especially those in containers with tap gestures
3. **Keyboard**: Test keyboard dismiss on both devices
4. **Rotation**: Test landscape orientation on both devices
5. **Lists**: Scroll through lists with 50+ items

## 6. Common Pitfalls

### Pitfall 1: Forgetting iPad Testing

Always run on iPad simulator before PR. Issues often only appear on iPad due to:
- Different touch handling
- Larger tap targets
- Different sheet behavior

### Pitfall 2: Hardcoded Sizes

```swift
// ❌ WRONG
.frame(width: 320)  // iPhone-specific

// ✅ CORRECT
.frame(maxWidth: isCompact ? 320 : 480)
// Or better: use ResponsiveLayout
```

### Pitfall 3: Assuming Sheet Behavior

Sheets behave differently on iPad:
- Can appear as popovers
- Different default sizes
- May not dismiss on background tap

### Pitfall 4: Gesture Conflicts

Multiple gesture recognizers can conflict. Always test:
- Swipe gestures with scroll views
- Tap gestures with buttons
- Long press with drag gestures

## 7. Design System Integration

### Files to Reference

| File | Purpose |
|------|---------|
| `ResponsiveLayout.swift` | Device-specific sizing |
| `View+Extensions.swift` | `responsiveSheet()`, `dismissKeyboardOnTap()` |
| `ColorSystem.swift` | Theme colors |
| `Typography.swift` | Font definitions |
| `Spacing.swift` | Base spacing values |

### Adding New Responsive Properties

If you need a new responsive property:

1. Add to `ResponsiveLayout.swift`:
```swift
var myNewProperty: CGFloat {
    isCompact ? 16 : 24
}
```

2. Document in this file and `RESPONSIVE-LAYOUT.md`

3. Use consistently across all views

## 8. Quick Reference

### Size Class Detection

```swift
@Environment(\.horizontalSizeClass) private var sizeClass
private var isCompact: Bool { sizeClass == .compact }
```

### Responsive Sheet

```swift
.responsiveSheet()
```

### Safe Keyboard Dismissal

```swift
.simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
// or
.dismissKeyboardOnTap()
```

### Layout Access

```swift
private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }
```
