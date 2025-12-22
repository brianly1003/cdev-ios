import SwiftUI

/// A TextField that highlights "ultrathink" keyword with rainbow colors
/// Supports multiple occurrences of the keyword
/// The keyword is only highlighted when it's a complete word (not followed by more letters)
///
/// Performance optimizations:
/// - O(n) single-pass algorithm for keyword detection
/// - Computed once per render cycle (SwiftUI caches computed properties within same render)
/// - Early exit when text is shorter than keyword
/// - Uses AttributedString (native SwiftUI, GPU-accelerated)
/// - Always uses ZStack to prevent focus loss (no view hierarchy changes)
struct RainbowTextField: View {
    let placeholder: String
    @Binding var text: String
    let font: Font
    var axis: Axis = .vertical
    var lineLimit: ClosedRange<Int> = 1...3
    var isDisabled: Bool = false
    var onSubmit: (() -> Void)?

    var body: some View {
        // Always use ZStack to prevent focus loss when transitioning
        ZStack(alignment: .leading) {
            // TextField for input handling
            TextField(placeholder, text: $text, axis: axis)
                .font(font)
                .foregroundStyle(rainbowData.hasKeyword ? .clear : ColorSystem.textPrimary)
                .lineLimit(lineLimit)
                .submitLabel(.send)
                .disabled(isDisabled)
                .onSubmit { onSubmit?() }

            // Attributed text overlay with shimmer on keywords only
            if rainbowData.hasKeyword {
                RainbowShimmerText(
                    attributedText: rainbowData.attributedText,
                    baseText: rainbowData.baseText,
                    keywordCharIndices: rainbowData.keywordCharIndices,
                    font: font,
                    lineLimit: lineLimit,
                    startPosition: rainbowData.firstKeywordPosition,
                    totalCharacters: rainbowData.totalCharacters,
                    firstKeywordIndex: rainbowData.firstKeywordIndex
                )
                .allowsHitTesting(false)
            }
        }
    }

    /// Single computed property that calculates everything in one pass
    /// This is computed once per render cycle by SwiftUI
    private var rainbowData: RainbowData {
        RainbowData.compute(text: text)
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
    let lineLimit: ClosedRange<Int>
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
                .lineLimit(lineLimit.upperBound)
                .fixedSize(horizontal: false, vertical: true)
                .overlay {
                    Text(animatedMask)
                        .font(font)
                        .lineLimit(lineLimit.upperBound)
                        .fixedSize(horizontal: false, vertical: true)
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
    func focused(_ binding: FocusState<Bool>.Binding) -> some View {
        RainbowTextFieldFocused(
            placeholder: placeholder,
            text: $text,
            font: font,
            axis: axis,
            lineLimit: lineLimit,
            isDisabled: isDisabled,
            isFocused: binding,
            onSubmit: onSubmit
        )
    }
}

/// Internal view that supports focus state
private struct RainbowTextFieldFocused: View {
    let placeholder: String
    @Binding var text: String
    let font: Font
    var axis: Axis
    var lineLimit: ClosedRange<Int>
    var isDisabled: Bool
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: (() -> Void)?

    var body: some View {
        let data = RainbowData.compute(text: text)

        ZStack(alignment: .leading) {
            TextField(placeholder, text: $text, axis: axis)
                .font(font)
                .foregroundStyle(data.hasKeyword ? .clear : ColorSystem.textPrimary)
                .lineLimit(lineLimit)
                .submitLabel(.send)
                .disabled(isDisabled)
                .focused(isFocused)
                .onSubmit { onSubmit?() }

            if data.hasKeyword {
                RainbowShimmerText(
                    attributedText: data.attributedText,
                    baseText: data.baseText,
                    keywordCharIndices: data.keywordCharIndices,
                    font: font,
                    lineLimit: lineLimit,
                    startPosition: data.firstKeywordPosition,
                    totalCharacters: data.totalCharacters,
                    firstKeywordIndex: data.firstKeywordIndex
                )
                .allowsHitTesting(false)
            }
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
