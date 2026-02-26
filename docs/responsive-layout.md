# Responsive Layout System

A centralized, reusable layout system for building responsive UIs across iPhone and iPad devices.

## Quick Start

```swift
struct MyView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        Text("Hello")
            .font(layout.bodyFont)
            .padding(.horizontal, layout.standardPadding)
    }
}
```

## Why Use ResponsiveLayout?

| Without ResponsiveLayout | With ResponsiveLayout |
|--------------------------|----------------------|
| Manual `isCompact` checks everywhere | Single `layout` object |
| Inconsistent sizing across views | Consistent design system |
| Hard to maintain | Easy to update globally |
| Verbose ternary expressions | Clean property access |

### Before (Verbose)
```swift
@Environment(\.horizontalSizeClass) private var sizeClass
private var isCompact: Bool { sizeClass == .compact }

// Repeated everywhere:
.font(.system(size: isCompact ? 12 : 14))
.padding(.horizontal, isCompact ? 12 : 16)
.frame(width: isCompact ? 32 : 36)
```

### After (Clean)
```swift
private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

// Simple property access:
.font(.system(size: layout.iconMedium))
.padding(.horizontal, layout.standardPadding)
.frame(width: layout.indicatorSize)
```

## Available Properties

### Spacing

| Property | iPhone (Compact) | iPad (Regular) | Usage |
|----------|------------------|----------------|-------|
| `smallPadding` | 8pt | 12pt | Tight spacing, inner padding |
| `standardPadding` | 12pt | 16pt | Default horizontal padding |
| `largePadding` | 16pt | 24pt | Section padding, outer margins |
| `contentSpacing` | 8pt | 12pt | Space between elements in a row |
| `sectionSpacing` | 16pt | 24pt | Space between sections |

### Icon Sizes

| Property | iPhone | iPad | Usage |
|----------|--------|------|-------|
| `iconSmall` | 9pt | 10pt | Status indicators, badges |
| `iconMedium` | 12pt | 14pt | Row icons, buttons |
| `iconLarge` | 16pt | 18pt | Primary actions, headers |
| `iconXLarge` | 24pt | 28pt | Empty states, hero icons |

### Component Sizes

| Property | iPhone | iPad | Usage |
|----------|--------|------|-------|
| `buttonHeight` | 32pt | 40pt | Standard buttons |
| `buttonHeightSmall` | 28pt | 32pt | Compact buttons |
| `inputHeight` | 40pt | 48pt | Text fields |
| `indicatorSize` | 32pt | 36pt | Status indicators, avatars |
| `indicatorSizeSmall` | 12pt | 14pt | Inline status dots |
| `dotSize` | 6pt | 7pt | Status dots |
| `avatarSize` | 32pt | 40pt | User avatars, thumbnails |

### Typography

| Property | iPhone | iPad | Usage |
|----------|--------|------|-------|
| `bodyFont` | `Typography.body` | `Typography.bodyBold` | Main content |
| `captionFont` | `Typography.caption1` | `Typography.body` | Secondary text |
| `labelFont` | `Typography.caption1` | `Typography.body` | Button labels |
| `terminalFont` | `Typography.terminal` | `Typography.terminal` | Code output |

### Line Widths & Shadows

| Property | iPhone | iPad | Usage |
|----------|--------|------|-------|
| `borderWidth` | 1pt | 1.5pt | Standard borders |
| `borderWidthThick` | 1.5pt | 2pt | Emphasized borders |
| `dividerWidth` | 0.5pt | 1pt | Divider lines |
| `shadowRadius` | 4pt | 6pt | Standard shadows |
| `shadowRadiusLarge` | 8pt | 12pt | Elevated components |

## Usage Patterns

### Pattern 1: Basic View

```swift
struct CompactRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: layout.contentSpacing) {
            Image(systemName: icon)
                .font(.system(size: layout.iconMedium))
                .foregroundStyle(ColorSystem.primary)

            Text(title)
                .font(layout.bodyFont)
                .foregroundStyle(ColorSystem.textPrimary)

            Spacer()
        }
        .padding(.horizontal, layout.standardPadding)
        .padding(.vertical, layout.smallPadding)
    }
}
```

### Pattern 2: Component with Multiple Sizes

```swift
struct StatusBadge: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    let status: Status

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: layout.dotSize, height: layout.dotSize)

            Text(status.label)
                .font(layout.captionFont)
        }
        .padding(.horizontal, layout.smallPadding)
        .padding(.vertical, layout.smallPadding / 2)
        .background(status.color.opacity(0.15))
        .clipShape(Capsule())
    }
}
```

### Pattern 3: Animated Indicator

```swift
struct LoadingIndicator: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(ColorSystem.primary, lineWidth: layout.borderWidthThick)
            .frame(width: layout.indicatorSize, height: layout.indicatorSize)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
```

### Pattern 4: Card Component

```swift
struct InfoCard: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    let title: String
    let message: String
    let icon: String

    var body: some View {
        HStack(spacing: layout.contentSpacing) {
            Image(systemName: icon)
                .font(.system(size: layout.iconLarge))
                .foregroundStyle(ColorSystem.primary)
                .frame(width: layout.avatarSize, height: layout.avatarSize)
                .background(ColorSystem.primary.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(layout.bodyFont)
                    .foregroundStyle(ColorSystem.textPrimary)

                Text(message)
                    .font(layout.captionFont)
                    .foregroundStyle(ColorSystem.textSecondary)
            }

            Spacer()
        }
        .padding(layout.standardPadding)
        .background(ColorSystem.terminalBgElevated)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .shadow(color: .black.opacity(0.1), radius: layout.shadowRadius)
    }
}
```

## Convenience Extensions

### Responsive Padding

```swift
// Apply standard responsive padding
.responsivePadding(sizeClass)

// Apply large responsive padding
.responsivePaddingLarge(sizeClass)
```

### Conditional Content

Show different content for iPhone vs iPad:

```swift
ResponsiveContent(
    compact: {
        // iPhone layout - stacked
        VStack { ... }
    },
    regular: {
        // iPad layout - side by side
        HStack { ... }
    }
)
```

## Best Practices

### DO

```swift
// Use layout properties consistently
.padding(.horizontal, layout.standardPadding)
.font(.system(size: layout.iconMedium))

// Combine with ColorSystem and Typography
Text("Title")
    .font(layout.bodyFont)  // or Typography.body for non-responsive
    .foregroundStyle(ColorSystem.textPrimary)

// Use semantic names
layout.indicatorSize  // Not: isCompact ? 32 : 36
```

### DON'T

```swift
// Don't hardcode sizes
.padding(.horizontal, 12)  // Bad
.font(.system(size: 14))   // Bad

// Don't use raw ternaries for common patterns
.frame(width: isCompact ? 32 : 36)  // Bad - use layout.indicatorSize

// Don't mix systems
.font(.body)  // Bad - use Typography or layout fonts
```

## Adding New Properties

If you need a new responsive value, add it to `ResponsiveLayout.swift`:

```swift
// In ResponsiveLayout struct:

/// My new custom size
var myCustomSize: CGFloat { isCompact ? 20 : 24 }
```

This ensures:
1. Consistent values across the app
2. Single place to update
3. Clear documentation of iPhone/iPad sizes

## File Location

`cdev/Core/Design/ResponsiveLayout.swift`

## Related Files

- `cdev/Core/Design/ColorSystem.swift` - Color palette
- `cdev/Core/Design/Typography.swift` - Font definitions
- `cdev/Core/Utilities/Spacing.swift` - Base spacing values
- `cdev/Core/Design/Animations.swift` - Animation presets
