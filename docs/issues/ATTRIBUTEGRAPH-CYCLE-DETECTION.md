# AttributeGraph Cycle Detection in SwiftUI

## Issue

Using `onChange` to sync local `@State` with ViewModel `@Published` properties can cause `AttributeGraph: cycle detected` errors.

## Symptoms

```
=== AttributeGraph: cycle detected through attribute 387936 ===
```

## Root Cause

When `onChange(of: localState)` updates a ViewModel `@Published` property, it triggers a publish, which causes SwiftUI to re-render, which may trigger `onChange` again, creating a cycle.

## Example - Problematic Code

```swift
// ❌ WRONG - Causes cycle
struct CommitHistoryView: View {
    @State private var searchText = ""
    @StateObject var viewModel: CommitHistoryViewModel

    var body: some View {
        TextField("Search", text: $searchText)
        ForEach(viewModel.filteredCommits) { ... }
    }
    .onChange(of: searchText) { _, newValue in
        viewModel.filterText = newValue  // Triggers @Published, causes cycle
    }
}
```

## Solution

Use local computed properties for filtering instead of syncing state:

```swift
// ✅ CORRECT - Local filtering, no cycle
struct CommitHistoryView: View {
    @State private var searchText = ""
    @StateObject var viewModel: CommitHistoryViewModel

    private var filteredCommits: [GitCommitNode] {
        guard !searchText.isEmpty else { return viewModel.commits }
        let query = searchText.lowercased()
        return viewModel.commits.filter { commit in
            commit.subject.lowercased().contains(query) ||
            commit.author.lowercased().contains(query)
        }
    }

    var body: some View {
        TextField("Search", text: $searchText)
        ForEach(filteredCommits) { ... }  // Use local computed property
    }
}
```

## When This Pattern is Safe

- Using `onChange` for one-time actions (navigation, haptics, logging)
- Updating unrelated state that doesn't affect the current view hierarchy
- Syncing to external systems (persistence, analytics) without UI feedback

## Related Files

- `cdev/Presentation/Screens/SourceControl/CommitHistoryView.swift` - Fixed in this file
