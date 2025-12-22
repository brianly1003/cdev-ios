import Foundation
import SwiftUI

/// ViewModel for ⌘K Quick Switcher
/// Manages workspace search, fuzzy matching, and keyboard navigation
@MainActor
final class QuickSwitcherViewModel: ObservableObject {
    // MARK: - Published State

    @Published var searchText = ""
    @Published var selectedIndex = 0
    @Published var isVisible = false

    // MARK: - Dependencies

    private let workspaceStore: WorkspaceStore

    // MARK: - Computed Properties

    /// Filtered and scored workspaces based on fuzzy search
    var filteredWorkspaces: [Workspace] {
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)

        // Empty search - return recent workspaces
        guard !query.isEmpty else {
            return workspaceStore.recentWorkspaces
        }

        // Fuzzy search with scoring
        let scored = workspaceStore.workspaces.compactMap { workspace -> (workspace: Workspace, score: Int)? in
            if let score = fuzzyScore(query: query, text: workspace.name.lowercased()) {
                return (workspace, score)
            }
            // Also check host
            if let score = fuzzyScore(query: query, text: workspace.hostDisplay.lowercased()) {
                return (workspace, score / 2)  // Lower priority for host matches
            }
            // Also check branch
            if let branch = workspace.branch,
               let score = fuzzyScore(query: query, text: branch.lowercased()) {
                return (workspace, score / 3)  // Even lower priority for branch matches
            }
            return nil
        }

        // Sort by score (higher = better match)
        return scored
            .sorted { $0.score > $1.score }
            .map { $0.workspace }
    }

    /// Number of workspaces in filtered list
    var resultCount: Int {
        filteredWorkspaces.count
    }

    /// Currently selected workspace (for keyboard navigation)
    var selectedWorkspace: Workspace? {
        guard selectedIndex >= 0 && selectedIndex < resultCount else {
            return nil
        }
        return filteredWorkspaces[selectedIndex]
    }

    // MARK: - Init

    init(workspaceStore: WorkspaceStore) {
        self.workspaceStore = workspaceStore
    }

    // MARK: - Public Methods

    /// Show the quick switcher
    func show() {
        isVisible = true
        searchText = ""
        selectedIndex = 0
    }

    /// Hide the quick switcher
    func hide() {
        isVisible = false
        searchText = ""
        selectedIndex = 0
    }

    /// Select workspace by keyboard shortcut (⌘1-9)
    func selectByShortcut(index: Int) -> Workspace? {
        let workspaces = filteredWorkspaces
        guard index >= 0 && index < workspaces.count else {
            return nil
        }
        return workspaces[index]
    }

    /// Move selection up (↑ arrow key)
    func moveSelectionUp() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    /// Move selection down (↓ arrow key)
    func moveSelectionDown() {
        if selectedIndex < resultCount - 1 {
            selectedIndex += 1
        }
    }

    /// Reset selection to top when search changes
    func resetSelection() {
        selectedIndex = 0
    }

    // MARK: - Fuzzy Search Algorithm

    /// Fuzzy matching score (higher = better match)
    /// Returns nil if no match, otherwise score based on:
    /// - Consecutive character matches (bonus)
    /// - Early matches (bonus)
    /// - Total matched characters
    ///
    /// Example: "mes" matches "messenger-integrator" (score ~60)
    ///          "cdev" matches "cdev-ios" (score ~100)
    private func fuzzyScore(query: String, text: String) -> Int? {
        guard !query.isEmpty && !text.isEmpty else { return nil }

        let queryChars = Array(query)
        let textChars = Array(text)

        var queryIndex = 0
        var textIndex = 0
        var score = 0
        var consecutiveMatches = 0
        var matchedIndices: [Int] = []

        // Find all matches
        while queryIndex < queryChars.count && textIndex < textChars.count {
            if queryChars[queryIndex] == textChars[textIndex] {
                // Match found
                score += 10
                matchedIndices.append(textIndex)

                // Bonus for consecutive matches
                if consecutiveMatches > 0 {
                    score += consecutiveMatches * 5
                }
                consecutiveMatches += 1

                // Bonus for early matches
                if textIndex < 3 {
                    score += 20
                }

                queryIndex += 1
            } else {
                consecutiveMatches = 0
            }

            textIndex += 1
        }

        // Must match all query characters
        guard queryIndex == queryChars.count else {
            return nil
        }

        // Bonus for exact prefix match
        if matchedIndices.first == 0 {
            score += 30
        }

        // Penalty for long gaps between matches
        if matchedIndices.count > 1 {
            for i in 0..<(matchedIndices.count - 1) {
                let gap = matchedIndices[i + 1] - matchedIndices[i]
                if gap > 5 {
                    score -= gap
                }
            }
        }

        return score
    }
}
