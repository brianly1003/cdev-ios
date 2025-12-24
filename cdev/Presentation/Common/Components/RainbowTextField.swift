import SwiftUI
import UIKit

/// Preference key for tracking view sizes
struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// A TextField that highlights "ultrathink" keyword with rainbow colors
/// Uses UITextView under the hood for proper scrolling with AttributedString support
/// Shows animated shimmer when not editing AND content fits (no scroll needed)
///
/// Responsive: Adapts padding and sizing for iPhone (compact) vs iPad (regular)
struct RainbowTextField: View {
    let placeholder: String
    @Binding var text: String
    let font: Font
    var axis: Axis = .vertical
    var lineLimit: ClosedRange<Int> = 1...3
    var maxHeight: CGFloat = 100
    var isDisabled: Bool = false
    var onSubmit: (() -> Void)?

    @State private var isEditing = false
    @State private var requestFocus = false
    @State private var contentHeight: CGFloat = 0
    @State private var cachedRainbowData: RainbowData?
    @State private var lastProcessedText: String = ""

    // Responsive layout for iPad/iPhone
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    /// Cached rainbow data - only recomputes when text changes
    private var rainbowData: RainbowData {
        // Use cached value if text hasn't changed
        if let cached = cachedRainbowData, lastProcessedText == text {
            return cached
        }
        return RainbowData.compute(text: text)
    }

    // Only show shimmer when content fits without scrolling
    private var shouldShowShimmer: Bool {
        !isEditing && rainbowData.hasKeyword && contentHeight <= maxHeight
    }

    // Responsive padding values
    private var horizontalPadding: CGFloat { layout.isCompact ? 5 : 7 }
    private var verticalPadding: CGFloat { layout.isCompact ? 4 : 6 }
    private var fontSize: CGFloat { layout.isCompact ? 13 : 14 }

    var body: some View {
        let data = rainbowData  // Compute once per render
        let showShimmer = !isEditing && data.hasKeyword && contentHeight <= maxHeight

        ZStack(alignment: .topLeading) {
            // UITextView for input - always present
            RainbowTextView(
                text: $text,
                placeholder: placeholder,
                maxHeight: maxHeight,
                isDisabled: isDisabled,
                onSubmit: onSubmit,
                isEditing: $isEditing,
                requestFocus: $requestFocus,
                contentHeight: $contentHeight,
                fontSize: fontSize,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding
            )
            // Hide text only when showing shimmer overlay
            .opacity(showShimmer ? 0.01 : 1)

            // Shimmer overlay - only when not editing, has keyword, AND content fits
            if showShimmer {
                RainbowShimmerText(
                    attributedText: data.attributedText,
                    baseText: data.baseText,
                    keywordCharIndices: data.keywordCharIndices,
                    font: font,
                    lineLimit: 1...100,
                    startPosition: data.firstKeywordPosition,
                    totalCharacters: data.totalCharacters,
                    firstKeywordIndex: data.firstKeywordIndex
                )
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Explicitly request focus when tapping shimmer overlay
                    requestFocus = true
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Tap anywhere to focus (when not already editing)
            if !isEditing {
                requestFocus = true
            }
        }
        .onChange(of: text) { _, newText in
            // Update cache when text changes
            cachedRainbowData = RainbowData.compute(text: newText)
            lastProcessedText = newText
        }
    }
}

// MARK: - UITextView Wrapper

/// Custom UITextView that reports its intrinsic content size for SwiftUI layout
private class DynamicHeightTextView: UITextView {
    var maxHeight: CGFloat = 100
    var minHeight: CGFloat = 28  // Single line height - matches button size

    override var intrinsicContentSize: CGSize {
        let size = sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        let height = min(max(minHeight, size.height), maxHeight)
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }
}

/// UIViewRepresentable wrapper for UITextView with rainbow text support
private struct RainbowTextView: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let maxHeight: CGFloat
    let isDisabled: Bool
    let onSubmit: (() -> Void)?
    var isFocused: FocusState<Bool>.Binding?
    var onFocusChange: ((Bool) -> Void)?  // Callback for focus changes (workaround for FocusState limitation)
    @Binding var isEditing: Bool
    @Binding var requestFocus: Bool
    @Binding var contentHeight: CGFloat

    // Responsive sizing
    var fontSize: CGFloat = 13
    var horizontalPadding: CGFloat = 5
    var verticalPadding: CGFloat = 4

    func makeUIView(context: Context) -> DynamicHeightTextView {
        let textView = DynamicHeightTextView()
        textView.maxHeight = maxHeight
        textView.delegate = context.coordinator
        textView.isScrollEnabled = false  // Start with scroll disabled, enable when needed
        textView.showsVerticalScrollIndicator = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(
            top: verticalPadding,
            left: horizontalPadding - 3,  // Slight inset adjustment
            bottom: verticalPadding,
            right: horizontalPadding - 3
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.font = UIFont.systemFont(ofSize: fontSize)
        textView.isEditable = !isDisabled
        textView.keyboardDismissMode = .interactive

        // Store fontSize in coordinator for later use
        context.coordinator.fontSize = fontSize

        // Set content hugging and compression resistance for dynamic height
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)

        return textView
    }

    func updateUIView(_ textView: DynamicHeightTextView, context: Context) {
        // Update coordinator's parent reference to get latest values
        context.coordinator.parent = self

        textView.maxHeight = maxHeight
        textView.isEditable = !isDisabled

        // Check if text actually changed (from external source, not from typing)
        let currentText = textView.text ?? ""
        if currentText != text {
            // Text changed externally - update the text view
            updateAttributedText(textView, context: context)
        }
        // Note: We don't update attributes on every keystroke to avoid keyboard dismissal
        // Rainbow colors will be applied when text changes externally or on initial load

        // Update placeholder visibility
        context.coordinator.updatePlaceholder(textView, isEmpty: text.isEmpty)

        // Calculate height and enable/disable scrolling (only if bounds are valid)
        if textView.bounds.width > 0 {
            let size = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
            let shouldScroll = size.height > maxHeight
            if textView.isScrollEnabled != shouldScroll {
                textView.isScrollEnabled = shouldScroll
            }
            // Report content height for shimmer decision
            if contentHeight != size.height {
                DispatchQueue.main.async {
                    self.contentHeight = size.height
                }
            }
        }

        // Handle focus request from tap gesture
        if requestFocus && !textView.isFirstResponder {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
            // Reset the flag
            DispatchQueue.main.async {
                self.requestFocus = false
            }
        }

        // Handle focus state binding - only when explicitly requested to focus
        if let isFocused = isFocused, isFocused.wrappedValue, !textView.isFirstResponder {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }
    }

    private func updateAttributedText(_ textView: UITextView, context: Context) {
        let data = RainbowData.compute(text: text)
        let currentFontSize = context.coordinator.fontSize

        // Set flag to prevent textViewDidChange from firing during programmatic update
        context.coordinator.isUpdatingText = true
        defer { context.coordinator.isUpdatingText = false }

        // Save first responder state - setting attributedText can dismiss keyboard
        let wasFirstResponder = textView.isFirstResponder

        if data.hasKeyword {
            // Build NSAttributedString with rainbow colors
            let nsAttrString = NSMutableAttributedString(string: text)

            // Apply base text color and font (responsive)
            let textColor = UIColor(ColorSystem.textPrimary)
            let textFont = UIFont.systemFont(ofSize: currentFontSize)
            nsAttrString.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: text.count))
            nsAttrString.addAttribute(.font, value: textFont, range: NSRange(location: 0, length: text.count))

            // Apply rainbow colors to keyword characters
            for (index, char) in text.enumerated() {
                if data.keywordCharIndices.contains(index) {
                    let color = RainbowTextView.rainbowColor(for: index, in: data)
                    nsAttrString.addAttribute(.foregroundColor, value: color, range: NSRange(location: index, length: 1))
                }

                // Check for bash mode "!" at start
                if char == "!" && index == 0 {
                    let bashColor = UIColor(ColorSystem.success)
                    nsAttrString.addAttribute(.foregroundColor, value: bashColor, range: NSRange(location: index, length: 1))
                }
            }

            textView.attributedText = nsAttrString
        } else {
            // No keyword - use plain text with normal color
            textView.text = text
            textView.textColor = UIColor(ColorSystem.textPrimary)
            textView.font = UIFont.systemFont(ofSize: currentFontSize)
        }

        // Restore first responder if it was lost
        if wasFirstResponder && !textView.isFirstResponder {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }
    }

    static func rainbowColor(for charIndex: Int, in data: RainbowData) -> UIColor {
        let keywordLength = 10 // "ultrathink"

        // Rainbow colors matching Claude Code CLI
        let rainbowColors: [UIColor] = [
            UIColor(red: 224/255, green: 132/255, blue: 124/255, alpha: 1), // u - Coral
            UIColor(red: 231/255, green: 144/255, blue: 98/255, alpha: 1),  // l - Peach
            UIColor(red: 241/255, green: 197/255, blue: 111/255, alpha: 1), // t - Gold
            UIColor(red: 157/255, green: 198/255, blue: 137/255, alpha: 1), // r - Sage
            UIColor(red: 138/255, green: 169/255, blue: 216/255, alpha: 1), // a - Sky
            UIColor(red: 166/255, green: 151/255, blue: 200/255, alpha: 1), // t - Lavender
            UIColor(red: 197/255, green: 146/255, blue: 186/255, alpha: 1), // h - Mauve
            UIColor(red: 224/255, green: 132/255, blue: 124/255, alpha: 1), // i - Coral
            UIColor(red: 231/255, green: 144/255, blue: 98/255, alpha: 1),  // n - Peach
            UIColor(red: 241/255, green: 197/255, blue: 111/255, alpha: 1), // k - Gold
        ]

        // Find position within keyword (0-9)
        let sortedIndices = data.keywordCharIndices.sorted()
        var keywordPosition = 0
        for (i, idx) in sortedIndices.enumerated() {
            if idx == charIndex {
                keywordPosition = i % keywordLength
                break
            }
        }

        return rainbowColors[keywordPosition]
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: RainbowTextView
        var needsAttributeUpdate = false
        var isUpdatingText = false  // Prevent feedback loop
        var fontSize: CGFloat = 13  // Responsive font size
        private weak var placeholderLabel: UILabel?  // Weak to avoid retain cycle

        init(_ parent: RainbowTextView) {
            self.parent = parent
        }

        deinit {
            // Clean up placeholder label if still exists
            placeholderLabel?.removeFromSuperview()
        }

        func updatePlaceholder(_ textView: UITextView, isEmpty: Bool) {
            if placeholderLabel == nil {
                let label = UILabel()
                label.text = parent.placeholder
                label.font = UIFont.systemFont(ofSize: fontSize)
                label.textColor = UIColor(ColorSystem.textTertiary)
                label.translatesAutoresizingMaskIntoConstraints = false
                textView.addSubview(label)
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: parent.horizontalPadding),
                    label.centerYAnchor.constraint(equalTo: textView.centerYAnchor)
                ])
                placeholderLabel = label
            }
            // Update placeholder text in case it changed (e.g., bash mode toggle)
            placeholderLabel?.text = parent.placeholder
            placeholderLabel?.isHidden = !isEmpty
        }

        func textViewDidChange(_ textView: UITextView) {
            // Skip if we're programmatically updating text
            guard !isUpdatingText else { return }

            let newText = textView.text ?? ""
            parent.text = newText
            placeholderLabel?.isHidden = !newText.isEmpty

            // Apply rainbow colors while typing (if keyword present)
            let data = RainbowData.compute(text: newText)
            if data.hasKeyword {
                isUpdatingText = true
                let selectedRange = textView.selectedRange

                // Build attributed string with rainbow colors (responsive font)
                let nsAttrString = NSMutableAttributedString(string: newText)
                let textColor = UIColor(ColorSystem.textPrimary)
                let textFont = UIFont.systemFont(ofSize: fontSize)
                nsAttrString.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: newText.count))
                nsAttrString.addAttribute(.font, value: textFont, range: NSRange(location: 0, length: newText.count))

                // Apply rainbow colors to keyword characters
                for (index, char) in newText.enumerated() {
                    if data.keywordCharIndices.contains(index) {
                        let color = RainbowTextView.rainbowColor(for: index, in: data)
                        nsAttrString.addAttribute(.foregroundColor, value: color, range: NSRange(location: index, length: 1))
                    }
                    // Bash mode "!" at start
                    if char == "!" && index == 0 {
                        nsAttrString.addAttribute(.foregroundColor, value: UIColor(ColorSystem.success), range: NSRange(location: index, length: 1))
                    }
                }

                textView.attributedText = nsAttrString

                // Restore cursor position
                if selectedRange.location <= newText.count {
                    textView.selectedRange = selectedRange
                }
                isUpdatingText = false
            }

            // Force layout update for height change
            if let dynamicTextView = textView as? DynamicHeightTextView {
                dynamicTextView.invalidateIntrinsicContentSize()
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isEditing = true
            // Notify parent of focus change (called synchronously for reliability)
            parent.onFocusChange?(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isEditing = false
            parent.onFocusChange?(false)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Always allow text changes including newlines
            // Submit is handled by the Send button, not Enter key
            return true
        }
    }
}

// MARK: - Shimmer Effect

/// Applies a sweeping white glare/shimmer animation on keyword characters only
/// Supports multi-line text - shimmer flows character by character (follows text flow)
///
/// Complexity per frame:
/// - Time: O(n) for AttributedString creation (unavoidable for SwiftUI Text)
/// - But O(1) lookup for each character using Set<Int>
/// - Space: O(n) for output AttributedString
private struct RainbowShimmerText: View {
    let attributedText: AttributedString
    let baseText: String
    let keywordCharIndices: Set<Int>  // O(1) lookup
    let font: Font
    let lineLimit: ClosedRange<Int>  // Match TextField line limit
    let startPosition: CGFloat
    let totalCharacters: Int
    let firstKeywordIndex: Int

    // Shimmer configuration
    private let shimmerWidth = 5  // Narrower shimmer
    private let cycleTime = 3.0  // Slower animation

    var body: some View {
        TimelineView(.animation) { context in
            let currentChar = calculateCurrentChar(time: context.date.timeIntervalSinceReferenceDate)
            let animatedMask = createOptimizedMask(centerChar: currentChar)

            Text(attributedText)
                .font(font)
                .lineSpacing(4)  // Match TextField line spacing
                .lineLimit(lineLimit.upperBound)  // Allow all lines to display
                .overlay {
                    Text(animatedMask)
                        .font(font)
                        .lineSpacing(4)  // Match TextField line spacing
                        .lineLimit(lineLimit.upperBound)  // Match base text
                        .blendMode(.plusLighter)
                }
        }
    }

    /// O(1) calculation of current shimmer position
    @inline(__always)
    private func calculateCurrentChar(time: TimeInterval) -> Int {
        let normalizedTime = (time.truncatingRemainder(dividingBy: cycleTime)) / cycleTime
        let startChar = firstKeywordIndex
        let endChar = totalCharacters + shimmerWidth
        return startChar + Int(normalizedTime * Double(endChar - startChar))
    }

    /// Optimized mask creation
    /// - Time: O(n) for string iteration (required for AttributedString)
    /// - Each character check is O(1) using Set lookup
    private func createOptimizedMask(centerChar: Int) -> AttributedString {
        var result = AttributedString()

        // Pre-calculate shimmer range for O(1) range check
        let shimmerStart = centerChar - shimmerWidth
        let shimmerEnd = centerChar + shimmerWidth

        for (index, char) in baseText.enumerated() {
            var charAttr = AttributedString(String(char))

            // O(1) Set lookup instead of iterating through runs
            if keywordCharIndices.contains(index) {
                // Character is part of a keyword - check if in shimmer range
                if index >= shimmerStart && index <= shimmerEnd {
                    let distance = abs(index - centerChar)
                    let intensity = 0.3 * (1.0 - (Double(distance) / Double(shimmerWidth)))  // Subtle brightness
                    charAttr.foregroundColor = .white.opacity(intensity)
                } else {
                    charAttr.foregroundColor = .clear
                }
            } else {
                // Not a keyword character - always clear
                charAttr.foregroundColor = .clear
            }

            result.append(charAttr)
        }

        return result
    }
}

// MARK: - Rainbow Data (Optimized Single-Pass Algorithm)

/// Holds pre-computed rainbow data to avoid multiple calculations
/// Complexity: Time O(n), Space O(n) for output only
private struct RainbowData {
    let hasKeyword: Bool
    let attributedText: AttributedString
    let baseText: String  // Original text for shimmer mask generation
    let keywordCharIndices: Set<Int>  // O(1) lookup for keyword characters
    let firstKeywordPosition: CGFloat
    let totalCharacters: Int
    let firstKeywordIndex: Int

    // Keyword as Character array for O(1) indexed access
    private static let keywordChars: [Character] = ["u", "l", "t", "r", "a", "t", "h", "i", "n", "k"]
    private static let keywordLength = 10

    // Max length to process - beyond this, skip rainbow styling for performance
    // Claude Code typical input: < 5000 chars, this gives 2x buffer
    private static let maxProcessLength = 10_000

    // Rainbow colors matching Claude Code CLI - static array, O(1) access
    private static let rainbowColors: [Color] = [
        Color(red: 224/255, green: 132/255, blue: 124/255), // u - Coral
        Color(red: 231/255, green: 144/255, blue: 98/255),  // l - Peach
        Color(red: 241/255, green: 197/255, blue: 111/255), // t - Gold
        Color(red: 157/255, green: 198/255, blue: 137/255), // r - Sage
        Color(red: 138/255, green: 169/255, blue: 216/255), // a - Sky
        Color(red: 166/255, green: 151/255, blue: 200/255), // t - Lavender
        Color(red: 197/255, green: 146/255, blue: 186/255), // h - Mauve
        Color(red: 224/255, green: 132/255, blue: 124/255), // i - Coral
        Color(red: 231/255, green: 144/255, blue: 98/255),  // n - Peach
        Color(red: 241/255, green: 197/255, blue: 111/255), // k - Gold
    ]

    /// TRUE Single-Pass O(n) Algorithm
    /// - Time: O(n) where n = text length
    /// - Space: O(n) for attributedText + O(k) for keywordCharIndices where k = keyword chars
    /// - Pre-computes keyword positions for O(1) lookup during animation
    /// - Also detects leading "!" for bash mode and colors it blue
    static func compute(text: String) -> RainbowData {
        let n = text.count

        // Early exit: text too short or too long (performance guard)
        guard n >= keywordLength, n <= maxProcessLength else {
            // Still check for bash mode even if text is short
            if n > 0 && text.hasPrefix("!") {
                return computeBashMode(text: text)
            }
            return RainbowData(
                hasKeyword: false,
                attributedText: AttributedString(),
                baseText: "",
                keywordCharIndices: [],
                firstKeywordPosition: 0,
                totalCharacters: 0,
                firstKeywordIndex: 0
            )
        }

        // Convert to array once for O(1) random access
        let chars = Array(text)

        var result = AttributedString()
        var keywordIndices = Set<Int>()  // O(1) lookup, O(k) space
        var hasKeyword = false
        var hasBashMode = false  // Track bash mode separately
        var firstKeywordIndex: Int = -1
        var i = 0

        while i < n {
            // BASH MODE: Check for leading "!" characters and color them green
            if chars[i] == "!" && (i == 0 || chars[0..<i].allSatisfy { $0.isWhitespace }) {
                hasBashMode = true  // Mark that we found bash mode
                var charAttr = AttributedString(String(chars[i]))
                charAttr.foregroundColor = ColorSystem.success  // Green for bash commands
                result.append(charAttr)
                i += 1
                continue
            }

            // Check if we can match keyword at position i
            if i <= n - keywordLength && matchesKeyword(chars: chars, at: i) {
                // Check word boundary
                let afterIndex = i + keywordLength
                let isValidBoundary = afterIndex >= n ||
                    chars[afterIndex].isWhitespace ||
                    chars[afterIndex].isPunctuation

                if isValidBoundary {
                    // Track first keyword position
                    if !hasKeyword {
                        firstKeywordIndex = i
                    }
                    hasKeyword = true

                    // Store keyword character indices for O(1) lookup
                    for j in 0..<keywordLength {
                        keywordIndices.insert(i + j)

                        var charAttr = AttributedString(String(chars[i + j]))
                        charAttr.foregroundColor = rainbowColors[j]
                        result.append(charAttr)
                    }

                    i += keywordLength
                    continue
                }
            }

            // No match - append single character as normal text
            var charAttr = AttributedString(String(chars[i]))
            charAttr.foregroundColor = ColorSystem.textPrimary
            result.append(charAttr)

            i += 1
        }

        // Calculate relative position (0.0 to 1.0) of first keyword
        let firstPosition = hasKeyword ? CGFloat(firstKeywordIndex) / CGFloat(n) : 0

        return RainbowData(
            hasKeyword: hasKeyword || hasBashMode,  // Show overlay if we have keywords OR bash mode
            attributedText: result,
            baseText: text,
            keywordCharIndices: keywordIndices,
            firstKeywordPosition: firstPosition,
            totalCharacters: n,
            firstKeywordIndex: firstKeywordIndex >= 0 ? firstKeywordIndex : 0
        )
    }

    /// Case-insensitive keyword match at position - O(10) = O(1) constant time
    @inline(__always)
    private static func matchesKeyword(chars: [Character], at index: Int) -> Bool {
        for j in 0..<keywordLength {
            if chars[index + j].lowercased() != String(keywordChars[j]) {
                return false
            }
        }
        return true
    }

    /// Compute bash mode styling for short text (just leading "!" in green)
    /// Used when text is too short for main algorithm but starts with "!"
    private static func computeBashMode(text: String) -> RainbowData {
        var result = AttributedString()
        let chars = Array(text)

        for (index, char) in chars.enumerated() {
            var charAttr = AttributedString(String(char))

            // Color leading "!" green, rest as normal text
            if char == "!" && (index == 0 || chars[0..<index].allSatisfy { $0.isWhitespace }) {
                charAttr.foregroundColor = ColorSystem.success  // Green for bash commands
            } else {
                charAttr.foregroundColor = ColorSystem.textPrimary
            }

            result.append(charAttr)
        }

        return RainbowData(
            hasKeyword: true,  // Has styled content (bash mode "!")
            attributedText: result,
            baseText: text,
            keywordCharIndices: [],  // Empty set = no shimmer effect
            firstKeywordPosition: 0,
            totalCharacters: text.count,
            firstKeywordIndex: 0
        )
    }
}

// MARK: - Focused Variant

extension RainbowTextField {
    /// Creates a RainbowTextField with focus binding support
    func focused(_ binding: FocusState<Bool>.Binding, onFocusChange: ((Bool) -> Void)? = nil) -> some View {
        RainbowTextFieldFocused(
            placeholder: placeholder,
            text: $text,
            font: font,
            axis: axis,
            lineLimit: lineLimit,
            maxHeight: maxHeight,
            isDisabled: isDisabled,
            isFocused: binding,
            onFocusChange: onFocusChange,
            onSubmit: onSubmit
        )
    }
}

/// Internal view that supports focus state
/// Responsive: Adapts padding and sizing for iPhone (compact) vs iPad (regular)
private struct RainbowTextFieldFocused: View {
    let placeholder: String
    @Binding var text: String
    let font: Font
    var axis: Axis
    var lineLimit: ClosedRange<Int>
    var maxHeight: CGFloat
    var isDisabled: Bool
    var isFocused: FocusState<Bool>.Binding
    var onFocusChange: ((Bool) -> Void)?  // External callback for focus changes
    var onSubmit: (() -> Void)?

    @State private var isEditing = false
    @State private var requestFocus = false
    @State private var contentHeight: CGFloat = 0
    @State private var cachedRainbowData: RainbowData?
    @State private var lastProcessedText: String = ""

    // Responsive layout for iPad/iPhone
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    /// Cached rainbow data - only recomputes when text changes
    private var rainbowData: RainbowData {
        if let cached = cachedRainbowData, lastProcessedText == text {
            return cached
        }
        return RainbowData.compute(text: text)
    }

    // Only show shimmer when content fits without scrolling
    private var shouldShowShimmer: Bool {
        !isEditing && rainbowData.hasKeyword && contentHeight <= maxHeight
    }

    // Responsive padding values
    private var horizontalPadding: CGFloat { layout.isCompact ? 5 : 7 }
    private var verticalPadding: CGFloat { layout.isCompact ? 4 : 6 }
    private var fontSize: CGFloat { layout.isCompact ? 13 : 14 }

    var body: some View {
        let data = rainbowData  // Compute once per render
        let showShimmer = !isEditing && data.hasKeyword && contentHeight <= maxHeight

        ZStack(alignment: .topLeading) {
            // UITextView for input - always present
            RainbowTextView(
                text: $text,
                placeholder: placeholder,
                maxHeight: maxHeight,
                isDisabled: isDisabled,
                onSubmit: onSubmit,
                isFocused: isFocused,
                isEditing: $isEditing,
                requestFocus: $requestFocus,
                contentHeight: $contentHeight,
                fontSize: fontSize,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding
            )
            // Hide text only when showing shimmer overlay
            .opacity(showShimmer ? 0.01 : 1)

            // Shimmer overlay - only when not editing, has keyword, AND content fits
            if showShimmer {
                RainbowShimmerText(
                    attributedText: data.attributedText,
                    baseText: data.baseText,
                    keywordCharIndices: data.keywordCharIndices,
                    font: font,
                    lineLimit: 1...100,
                    startPosition: data.firstKeywordPosition,
                    totalCharacters: data.totalCharacters,
                    firstKeywordIndex: data.firstKeywordIndex
                )
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Explicitly request focus when tapping shimmer overlay
                    requestFocus = true
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Tap anywhere to focus (when not already editing)
            if !isEditing {
                requestFocus = true
            }
        }
        .onChange(of: text) { _, newText in
            // Update cache when text changes
            cachedRainbowData = RainbowData.compute(text: newText)
            lastProcessedText = newText
        }
        .onChange(of: isEditing) { _, newValue in
            // Propagate editing state changes to parent via callback
            // This is more reliable than UIViewRepresentable's callback chain
            onFocusChange?(newValue)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        // ✅ Should be rainbow - end of string
        RainbowTextField(
            placeholder: "Ask Claude...",
            text: .constant("ultrathink"),
            font: Typography.inputField
        )
        .padding()
        .background(ColorSystem.terminalBgHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 12))

        // ✅ Should be rainbow - followed by space
        RainbowTextField(
            placeholder: "Ask Claude...",
            text: .constant("ultrathink please"),
            font: Typography.inputField
        )
        .padding()
        .background(ColorSystem.terminalBgHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 12))

        // ✅ Should be rainbow - followed by punctuation
        RainbowTextField(
            placeholder: "Ask Claude...",
            text: .constant("ultrathink, do this"),
            font: Typography.inputField
        )
        .padding()
        .background(ColorSystem.terminalBgHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 12))

        // ✅ Multiple keywords
        RainbowTextField(
            placeholder: "Ask Claude...",
            text: .constant("ultrathink first then ultrathink again"),
            font: Typography.inputField
        )
        .padding()
        .background(ColorSystem.terminalBgHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 12))

        // ❌ Should NOT be rainbow - followed by letters
        RainbowTextField(
            placeholder: "Ask Claude...",
            text: .constant("ultrathinkAAAA"),
            font: Typography.inputField
        )
        .padding()
        .background(ColorSystem.terminalBgHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 12))

        // ❌ Should NOT be rainbow - followed by numbers
        RainbowTextField(
            placeholder: "Ask Claude...",
            text: .constant("ultrathink123"),
            font: Typography.inputField
        )
        .padding()
        .background(ColorSystem.terminalBgHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 12))

        // ✅ Case insensitive
        RainbowTextField(
            placeholder: "Ask Claude...",
            text: .constant("ULTRATHINK mode"),
            font: Typography.inputField
        )
        .padding()
        .background(ColorSystem.terminalBgHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .padding()
    .background(ColorSystem.terminalBg)
}
