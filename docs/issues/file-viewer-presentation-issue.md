# Sheet Presentation "Attempt to present while a presentation is in progress" Issue

## Status: RESOLVED

## Summary

When tapping to open a file/diff in views inside a paged TabView, the sheet would either:
1. Show "Attempt to present while a presentation is in progress" error and auto-dismiss
2. Show loading state forever without displaying content
3. Only open after switching to another tab

**Affected Views:**
- `ExplorerView` - File Viewer sheet
- `SourceControlView` - Diff Viewer sheet (issue appears when switching workspaces)

## Root Cause Analysis

### Issue 1: TabView Recreation

Views inside a paged `TabView` get recreated when swiping between tabs or when workspace state changes. Each recreation can trigger presentation handlers, causing multiple presentation attempts from different view instances.

**Evidence**: Logs showed TWO different `PresentationHostingController` addresses trying to present simultaneously.

### Issue 2: Nested ObservableObject (ExplorerView specific)

`DashboardView` observes `DashboardViewModel`, but `explorerViewModel` is a nested property. When `explorerViewModel.fileContent` or `explorerViewModel.isLoadingFile` changed, `DashboardView` didn't see these updates because SwiftUI only observes the direct `@Published` properties of the parent `ObservableObject`, not nested ones.

**Evidence**: FileViewerView showed "Loading..." forever even though logs showed file content was loaded successfully.

### Issue 3: Workspace Switch Triggers View Recreation

Even `SourceControlView` with local `@State` experienced the issue when switching workspaces. The workspace switch causes the entire view hierarchy to be recreated, and if a sheet was being presented during this transition, SwiftUI throws the "presentation in progress" error.

## Solution

### Fix 1: Hoist Sheet Presentation to DashboardView

Move all `sheet(item:)` modifiers from child views to `DashboardView` level, which is outside the `TabView` and won't be affected by page recreation or workspace switches.

**Files Changed:**
- `DashboardView.swift` - Added sheet presentations and state variables
- `ExplorerView.swift` - Removed sheet, added `onPresentFile` callback
- `SourceControlView.swift` - Removed sheet, added `onPresentDiff` callback

### Fix 2: Direct ObservableObject Reference (for async content)

For views that need to observe nested ViewModel properties (like `explorerViewModel.fileContent`), add a direct `@ObservedObject` reference:

```swift
// DashboardView.swift
@ObservedObject private var explorerViewModel: ExplorerViewModel

init(viewModel: DashboardViewModel) {
    _viewModel = StateObject(wrappedValue: viewModel)
    _explorerViewModel = ObservedObject(wrappedValue: viewModel.explorerViewModel)
}
```

### Fix 3: Callback Pattern for All Sheet Presentations

Use callbacks from child views to notify `DashboardView` when content should be presented:

```swift
// ExplorerView.swift
var onPresentFile: ((FileEntry) -> Void)?

.onChange(of: viewModel.selectedFile) { _, newFile in
    if let file = newFile {
        onPresentFile?(file)
    }
}

// SourceControlView.swift
var onPresentDiff: ((GitFileEntry) -> Void)?

onFileTap: { file in
    onPresentDiff?(file)
    Haptics.selection()
}

// DashboardView.swift
ExplorerView(
    viewModel: viewModel.explorerViewModel,
    onPresentFile: { file in
        guard !isFileDismissing && fileToDisplay == nil else { return }
        fileToDisplay = file
    }
)

SourceControlView(
    viewModel: viewModel.sourceControlViewModel,
    onPresentDiff: { file in
        diffFileToDisplay = file
    }
)

// Sheets at stable DashboardView level
.sheet(item: $fileToDisplay) { file in
    FileViewerView(file: file, ...)
}
.sheet(item: $diffFileToDisplay) { file in
    DiffDetailSheet(file: file)
}
```

## Why Local @State Wasn't Enough for SourceControlView

Initially, `SourceControlView` used local `@State` which typically persists across view identity recreations:

```swift
@State private var selectedFile: GitFileEntry?

.sheet(item: $selectedFile) { file in
    DiffDetailSheet(file: file)
}
```

However, this still failed during **workspace switches** because:
1. Workspace switch triggers major state changes in parent views
2. The entire view hierarchy gets recreated
3. If sheet presentation was in progress during recreation, SwiftUI throws the error

**Lesson**: Even with local `@State`, sheets inside paged TabView can fail during significant state transitions like workspace switches.

## Key Learnings

### 1. Avoid sheets inside paged TabView

TabView recreation can cause presentation race conditions.

**Not Good:**
```swift
// Sheet inside a view that's inside paged TabView
struct ExplorerView: View {
    @State private var fileToDisplay: FileEntry?

    var body: some View {
        VStack { ... }
        .sheet(item: $fileToDisplay) { file in
            FileViewerView(file: file)
        }
    }
}

// Parent view with paged TabView
TabView(selection: $selectedTab) {
    TerminalView().tag(.terminal)
    ExplorerView().tag(.explorer)  // Sheet here gets recreated!
}
.tabViewStyle(.page)
```

**Best Practice:**
```swift
// Sheet at parent level, outside TabView
struct DashboardView: View {
    @State private var fileToDisplay: FileEntry?

    var body: some View {
        TabView(selection: $selectedTab) {
            TerminalView().tag(.terminal)
            ExplorerView(onPresentFile: { file in
                fileToDisplay = file
            }).tag(.explorer)
        }
        .tabViewStyle(.page)
        .sheet(item: $fileToDisplay) { file in  // Sheet at stable level
            FileViewerView(file: file)
        }
    }
}
```

---

### 2. Nested ObservableObject pitfall

Changes to nested object properties don't automatically trigger parent view updates.

**Not Good:**
```swift
// Parent ViewModel with nested ViewModel
class DashboardViewModel: ObservableObject {
    let explorerViewModel = ExplorerViewModel()  // Nested object
}

// Parent View - won't see changes to explorerViewModel.fileContent!
struct DashboardView: View {
    @StateObject var viewModel: DashboardViewModel

    var body: some View {
        FileViewerView(
            content: viewModel.explorerViewModel.fileContent  // Won't update!
        )
    }
}
```

**Best Practice:**
```swift
// Option A: Add direct @ObservedObject reference
struct DashboardView: View {
    @StateObject var viewModel: DashboardViewModel
    @ObservedObject private var explorerViewModel: ExplorerViewModel

    init(viewModel: DashboardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _explorerViewModel = ObservedObject(wrappedValue: viewModel.explorerViewModel)
    }

    var body: some View {
        FileViewerView(
            content: explorerViewModel.fileContent  // Now updates correctly!
        )
    }
}

// Option B: Forward properties in parent ViewModel
class DashboardViewModel: ObservableObject {
    let explorerViewModel = ExplorerViewModel()

    @Published var fileContent: String? {
        didSet { explorerViewModel.fileContent = fileContent }
    }

    // Subscribe to child changes
    init() {
        explorerViewModel.$fileContent
            .assign(to: &$fileContent)
    }
}
```

---

### 3. Use callbacks for cross-view communication

More reliable than relying on observation of nested properties.

**Not Good:**
```swift
// Relying on onChange to observe nested property
struct ParentView: View {
    @StateObject var viewModel: ParentViewModel
    @State private var itemToShow: Item?

    var body: some View {
        ChildView(viewModel: viewModel.childViewModel)
        .onChange(of: viewModel.childViewModel.selectedItem) { _, item in
            itemToShow = item  // May not fire due to nested observation issue!
        }
    }
}
```

**Best Practice:**
```swift
// Use callback pattern
struct ChildView: View {
    @ObservedObject var viewModel: ChildViewModel
    var onSelectItem: ((Item) -> Void)?  // Callback

    var body: some View {
        List(items) { item in
            Button {
                viewModel.selectItem(item)
                onSelectItem?(item)  // Notify parent directly
            } label: {
                ItemRow(item: item)
            }
        }
    }
}

struct ParentView: View {
    @State private var itemToShow: Item?

    var body: some View {
        ChildView(
            viewModel: viewModel.childViewModel,
            onSelectItem: { item in
                itemToShow = item  // Reliable!
            }
        )
        .sheet(item: $itemToShow) { item in
            ItemDetailView(item: item)
        }
    }
}
```

---

### 4. Keep presentation state at stable hierarchy level

Present sheets from views that won't be recreated.

**Not Good:**
```swift
// Presentation state in frequently recreated view
struct ItemCell: View {
    let item: Item
    @State private var showDetail = false  // State lost on cell reuse!

    var body: some View {
        Button { showDetail = true } label: { ... }
        .sheet(isPresented: $showDetail) {
            DetailView(item: item)
        }
    }
}
```

**Best Practice:**
```swift
// Presentation state in stable parent view
struct ItemListView: View {
    @State private var selectedItem: Item?  // Stable state

    var body: some View {
        List(items) { item in
            Button {
                selectedItem = item
            } label: {
                ItemCell(item: item)
            }
        }
        .sheet(item: $selectedItem) { item in  // Single sheet at list level
            DetailView(item: item)
        }
    }
}
```

---

### 5. Local @State is NOT safe in paged TabView during state transitions

Even with local `@State`, sheets can fail during workspace switches or other major state changes.

**Not Good (fails on workspace switch):**
```swift
// Local state in view inside paged TabView
struct SourceControlView: View {
    @State private var selectedFile: GitFileEntry?  // Seems safe but isn't!

    var body: some View {
        List(files) { file in
            Button {
                selectedFile = file
            } label: {
                FileRow(file: file)
            }
        }
        .sheet(item: $selectedFile) { file in
            DiffDetailSheet(file: file)  // Fails during workspace switch!
        }
    }
}
```

**Best Practice (always hoist sheets outside TabView):**
```swift
// Callback pattern even for simple cases
struct SourceControlView: View {
    var onPresentDiff: ((GitFileEntry) -> Void)?

    var body: some View {
        List(files) { file in
            Button {
                onPresentDiff?(file)  // Let parent handle presentation
            } label: {
                FileRow(file: file)
            }
        }
    }
}

// Parent handles all sheets
struct DashboardView: View {
    @State private var diffFileToDisplay: GitFileEntry?

    var body: some View {
        TabView {
            SourceControlView(onPresentDiff: { file in
                diffFileToDisplay = file
            })
        }
        .tabViewStyle(.page)
        .sheet(item: $diffFileToDisplay) { file in
            DiffDetailSheet(file: file)  // Safe at parent level
        }
    }
}
```

## Related Files

- `cdev/Presentation/Screens/Dashboard/DashboardView.swift`
- `cdev/Presentation/Screens/Explorer/ExplorerView.swift`
- `cdev/Presentation/Screens/Explorer/ExplorerViewModel.swift`
- `cdev/Presentation/Screens/Explorer/Components/FileViewerView.swift`
- `cdev/Presentation/Screens/SourceControl/SourceControlView.swift`
