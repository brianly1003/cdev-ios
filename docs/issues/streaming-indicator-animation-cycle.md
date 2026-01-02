# Streaming Indicator Animation Cycle

## Issue

When Claude starts streaming (e.g., user sends a prompt), the app can enter an infinite `AttributeGraph: cycle detected` loop, causing the app to hang completely.

## Symptoms

```
[DashboardVM] claudeState: idle → running
[Dashboard] PTY spinner: Baking… (esc to interrupt)
[LogListView] Rendering: elements=15, logs=13, useElementsView=true
=== AttributeGraph: cycle detected through attribute 1009980 ===
=== AttributeGraph: cycle detected through attribute 1009980 ===
=== AttributeGraph: cycle detected through attribute 505484 ===
... (repeats indefinitely, app hangs)
```

The log file can grow to 28MB+ with these repeated messages.

## Root Cause

Multiple competing animations on the `isStreaming` state change created a circular dependency:

1. **Animation modifier on StreamingIndicatorView:**
   ```swift
   // ❌ PROBLEMATIC
   if isStreaming {
       StreamingIndicatorView(...)
           .transition(.move(edge: .bottom).combined(with: .opacity))
           .animation(.easeInOut(duration: 0.2), value: isStreaming)  // <- This
   }
   ```

2. **onChange handler triggering animated scroll:**
   ```swift
   // ❌ PROBLEMATIC
   .onChange(of: isStreaming) { _, streaming in
       guard streaming else { return }
       scheduleScroll(proxy: proxy, animated: true)  // <- Uses withAnimation internally
   }
   ```

The cycle:
1. `isStreaming` becomes `true`
2. `StreamingIndicatorView` appears with `.animation()` modifier
3. `.onChange(of: isStreaming)` fires, calls `scheduleScroll(animated: true)`
4. `scheduleScroll` uses `withAnimation(Animations.logAppear)` to scroll
5. Multiple animations interact, causing SwiftUI's AttributeGraph to detect a circular dependency
6. Infinite loop ensues

## BAD - Problematic Code

```swift
// ❌ BAD - Multiple animations on same state change cause cycle
struct ElementsScrollView: View {
    let isStreaming: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    // ... content ...
                }
                .onChange(of: isStreaming) { _, streaming in
                    guard streaming else { return }
                    // ❌ BAD: Animated scroll when isStreaming changes
                    scheduleScroll(proxy: proxy, animated: true)
                }
            }

            // Streaming indicator
            if isStreaming {
                StreamingIndicatorView(...)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    // ❌ BAD: Additional animation on same state
                    .animation(.easeInOut(duration: 0.2), value: isStreaming)
            }
        }
    }

    private func scheduleScroll(proxy: ScrollViewProxy, animated: Bool) {
        scrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            if animated {
                // ❌ BAD: withAnimation conflicts with .animation() modifier above
                withAnimation(Animations.logAppear) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}
```

## GOOD - Fixed Code

```swift
// ✅ GOOD - Single animation source, no conflicts
struct ElementsScrollView: View {
    let isStreaming: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    // ... content ...
                }
                .onChange(of: isStreaming) { _, streaming in
                    guard streaming else { return }
                    // ✅ GOOD: Non-animated scroll - indicator has its own animation
                    scheduleScroll(proxy: proxy, animated: false)
                }
            }

            // Streaming indicator
            if isStreaming {
                StreamingIndicatorView(...)
                    // ✅ GOOD: Only transition, no .animation() modifier
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func scheduleScroll(proxy: ScrollViewProxy, animated: Bool) {
        scrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            if animated {
                withAnimation(Animations.logAppear) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            } else {
                // ✅ GOOD: No animation conflict
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}
```

## Key Learnings

1. **Don't combine `.animation(value:)` with `.transition()` on the same conditional view** - They serve similar purposes and can conflict.

2. **Avoid multiple `withAnimation` calls that could run simultaneously** - When one state change triggers multiple animations, they can create cycles.

3. **Use non-animated operations in `onChange` when the triggering value already has associated animations** - The view will animate via its own modifiers; adding animation in the handler is redundant.

4. **Test streaming scenarios thoroughly** - This bug only manifests when Claude starts streaming, which might not be covered in basic UI testing.

## Related Files

- `cdev/Presentation/Screens/LogViewer/LogListView.swift` - ElementsScrollView and StreamingIndicatorView
- `cdev/Presentation/Screens/Dashboard/DashboardViewModel.swift` - isStreaming state management

## Fixed In

Commit `d218b25` - fix: prevent AttributeGraph cycle when streaming starts
