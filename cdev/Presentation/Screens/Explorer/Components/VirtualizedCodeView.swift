import SwiftUI
import UIKit

// MARK: - VirtualizedCodeView (UIKit-backed for performance)

/// High-performance code viewer using UICollectionView for true lazy loading
/// Supports synchronized horizontal scrolling across all lines via gesture
struct VirtualizedCodeView: UIViewRepresentable {
    let lines: [String]
    let fileExtension: String?
    let showLineNumbers: Bool
    let syntaxHighlighting: Bool
    let activeLineIndex: Int?
    let matchesByLine: [Int: [SearchMatch]]
    let currentMatch: SearchMatch?
    let onLineTap: ((Int) -> Void)?

    // Scroll to line request (for search navigation)
    var scrollToLine: Int?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> VirtualizedCodeCollectionView {
        AppLogger.log("[VirtualizedCodeView] makeUIView - lines: \(lines.count)")
        let view = VirtualizedCodeCollectionView(frame: .zero)
        view.configure(
            lines: lines,
            fileExtension: fileExtension,
            showLineNumbers: showLineNumbers,
            syntaxHighlighting: syntaxHighlighting,
            matchesByLine: matchesByLine,
            currentMatch: currentMatch
        )
        view.onLineTap = onLineTap
        return view
    }

    func updateUIView(_ uiView: VirtualizedCodeCollectionView, context: Context) {
        uiView.update(
            lines: lines,
            activeLineIndex: activeLineIndex,
            matchesByLine: matchesByLine,
            currentMatch: currentMatch,
            syntaxHighlighting: syntaxHighlighting
        )

        // Handle scroll to line request
        if let lineIndex = scrollToLine {
            uiView.scrollToLine(lineIndex, animated: true)
        }
    }

    class Coordinator: NSObject {
        var parent: VirtualizedCodeView

        init(_ parent: VirtualizedCodeView) {
            self.parent = parent
        }
    }
}

// MARK: - VirtualizedCodeCollectionView

/// UICollectionView-based code viewer with synchronized horizontal scrolling
/// - Vertical scroll: UICollectionView (lazy loading)
/// - Horizontal scroll: Only code content scrolls, gutter stays fixed
final class VirtualizedCodeCollectionView: UIView, UIScrollViewDelegate {
    // MARK: - Properties

    private var lines: [String] = []
    private var fileExtension: String?
    private var showLineNumbers: Bool = true
    private var syntaxHighlighting: Bool = true
    private var activeLineIndex: Int?
    private var matchesByLine: [Int: [SearchMatch]] = [:]
    private var currentMatch: SearchMatch?

    // Horizontal scroll offset (synced across all cells)
    private var horizontalOffset: CGFloat = 0
    private var maxContentWidth: CGFloat = 0

    // UI Components
    private var collectionView: UICollectionView!
    private var horizontalScrollBar: UIScrollView!  // Just for the scroll indicator

    // Layout constants
    private let lineHeight: CGFloat = 20
    private var gutterWidth: CGFloat = 36

    // Callbacks
    var onLineTap: ((Int) -> Void)?

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    // MARK: - Setup

    private func setupViews() {
        backgroundColor = UIColor(ColorSystem.Editor.background)

        // Create collection view layout
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        // Don't use estimatedItemSize - we set exact itemSize in updateLayout()
        layout.itemSize = CGSize(width: 300, height: lineHeight)

        // Create collection view for vertical scrolling with lazy loading
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.showsVerticalScrollIndicator = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.alwaysBounceVertical = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        // Register cell
        collectionView.register(CodeLineCell.self, forCellWithReuseIdentifier: CodeLineCell.reuseIdentifier)

        addSubview(collectionView)

        // Horizontal scroll bar at bottom (invisible content, just shows indicator)
        horizontalScrollBar = UIScrollView()
        horizontalScrollBar.showsHorizontalScrollIndicator = true
        horizontalScrollBar.showsVerticalScrollIndicator = false
        horizontalScrollBar.delegate = self
        horizontalScrollBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(horizontalScrollBar)

        // Layout constraints
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            horizontalScrollBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: gutterWidth),
            horizontalScrollBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            horizontalScrollBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            horizontalScrollBar.heightAnchor.constraint(equalToConstant: 8),
        ])

        // Add pan gesture for horizontal scrolling on collection view
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.delegate = self
        collectionView.addGestureRecognizer(panGesture)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayout()
    }

    private func updateLayout() {
        guard bounds.width > 0 && bounds.height > 0 else {
            AppLogger.log("[VirtualizedCode] updateLayout skipped - bounds: \(bounds)")
            return
        }

        // Calculate max content width based on longest line
        let maxLineLength = lines.max(by: { $0.count < $1.count })?.count ?? 0
        let codeAreaWidth = bounds.width - gutterWidth
        maxContentWidth = max(codeAreaWidth, CGFloat(maxLineLength) * 7.5 + 32)

        AppLogger.log("[VirtualizedCode] updateLayout - bounds: \(bounds.width)x\(bounds.height), gutterWidth: \(gutterWidth), codeAreaWidth: \(codeAreaWidth), maxLineLength: \(maxLineLength), maxContentWidth: \(maxContentWidth)")

        // Update horizontal scroll bar content size
        horizontalScrollBar.contentSize = CGSize(width: maxContentWidth, height: 1)

        // Update collection view layout
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            let newSize = CGSize(width: bounds.width, height: lineHeight)
            if layout.itemSize != newSize {
                layout.itemSize = newSize
                AppLogger.log("[VirtualizedCode] cell itemSize updated: \(layout.itemSize)")
                layout.invalidateLayout()
                // Force reload to apply new cell sizes
                collectionView.reloadData()
            }
        }
    }

    // MARK: - Horizontal Scroll via Pan Gesture

    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)

        switch gesture.state {
        case .changed:
            // Only handle if primarily horizontal
            if abs(translation.x) > abs(translation.y) * 0.3 {
                let codeAreaWidth = bounds.width - gutterWidth
                let maxOffset = max(0, maxContentWidth - codeAreaWidth)
                let newOffset = horizontalOffset - translation.x
                horizontalOffset = max(0, min(newOffset, maxOffset))
                gesture.setTranslation(.zero, in: self)
                updateVisibleCellsOffset()
                // Sync scroll bar
                horizontalScrollBar.contentOffset.x = horizontalOffset
            }
        case .ended, .cancelled:
            // Apply momentum
            let codeAreaWidth = bounds.width - gutterWidth
            let maxOffset = max(0, maxContentWidth - codeAreaWidth)
            let momentumOffset = horizontalOffset - velocity.x * 0.15
            let targetOffset = max(0, min(momentumOffset, maxOffset))

            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                self.horizontalOffset = targetOffset
                self.updateVisibleCellsOffset()
                self.horizontalScrollBar.contentOffset.x = targetOffset
            }
        default:
            break
        }
    }

    private func updateVisibleCellsOffset() {
        for cell in collectionView.visibleCells {
            if let codeCell = cell as? CodeLineCell {
                codeCell.setHorizontalOffset(horizontalOffset)
            }
        }
    }

    // MARK: - UIScrollViewDelegate (for horizontal scroll bar)

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == horizontalScrollBar {
            horizontalOffset = scrollView.contentOffset.x
            updateVisibleCellsOffset()
        }
    }

    // MARK: - Configuration

    func configure(
        lines: [String],
        fileExtension: String?,
        showLineNumbers: Bool,
        syntaxHighlighting: Bool,
        matchesByLine: [Int: [SearchMatch]],
        currentMatch: SearchMatch?
    ) {
        self.lines = lines
        self.fileExtension = fileExtension
        self.showLineNumbers = showLineNumbers
        self.syntaxHighlighting = syntaxHighlighting
        self.matchesByLine = matchesByLine
        self.currentMatch = currentMatch

        // Calculate gutter width based on line count
        let digitCount = String(lines.count).count
        gutterWidth = CGFloat(max(digitCount * 8 + 16, 36))

        collectionView.reloadData()
        updateLayout()
    }

    func update(
        lines: [String],
        activeLineIndex: Int?,
        matchesByLine: [Int: [SearchMatch]],
        currentMatch: SearchMatch?,
        syntaxHighlighting: Bool
    ) {
        let linesChanged = self.lines != lines
        self.lines = lines
        self.activeLineIndex = activeLineIndex
        self.matchesByLine = matchesByLine
        self.currentMatch = currentMatch
        self.syntaxHighlighting = syntaxHighlighting

        if linesChanged {
            collectionView.reloadData()
            updateLayout()
        } else {
            // Only reload visible cells for performance
            collectionView.reloadItems(at: collectionView.indexPathsForVisibleItems)
        }
    }

    func scrollToLine(_ lineIndex: Int, animated: Bool) {
        guard lineIndex >= 0 && lineIndex < lines.count else { return }
        let indexPath = IndexPath(item: lineIndex, section: 0)
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: animated)
    }
}

// MARK: - UICollectionViewDataSource

extension VirtualizedCodeCollectionView: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return lines.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CodeLineCell.reuseIdentifier, for: indexPath) as! CodeLineCell

        let lineIndex = indexPath.item
        let line = lines[lineIndex]
        let isActive = activeLineIndex == lineIndex
        let lineMatches = matchesByLine[lineIndex] ?? []
        let hasCurrentMatch = lineMatches.contains { $0 == currentMatch }

        cell.configure(
            lineNumber: lineIndex + 1,
            content: line,
            gutterWidth: gutterWidth,
            isActive: isActive,
            hasMatch: !lineMatches.isEmpty,
            hasCurrentMatch: hasCurrentMatch,
            lineMatches: lineMatches,
            currentMatch: currentMatch,
            syntaxHighlighting: syntaxHighlighting,
            fileExtension: fileExtension
        )

        // Apply current horizontal offset
        cell.setHorizontalOffset(horizontalOffset)

        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension VirtualizedCodeCollectionView: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onLineTap?(indexPath.item)
        collectionView.deselectItem(at: indexPath, animated: false)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension VirtualizedCodeCollectionView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow vertical scroll to work simultaneously with horizontal pan
        return true
    }
}

// MARK: - CodeLineCell

/// UICollectionViewCell for a single code line
final class CodeLineCell: UICollectionViewCell {
    static let reuseIdentifier = "CodeLineCell"

    // UI Components
    private let lineNumberLabel = UILabel()
    private let gutterSeparator = UIView()
    private let codeContainer = UIView()  // Clips code content
    private let codeLabel = UILabel()
    private let activeHighlight = UIView()

    // Layout
    private var gutterWidth: CGFloat = 36
    private var horizontalOffset: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        backgroundColor = .clear
        contentView.clipsToBounds = true

        // Active line highlight
        activeHighlight.backgroundColor = UIColor(ColorSystem.Editor.activeLineBg)
        activeHighlight.isHidden = true
        contentView.addSubview(activeHighlight)

        // Line number (fixed position, always visible)
        lineNumberLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        lineNumberLabel.textColor = UIColor(ColorSystem.Editor.lineNumber)
        lineNumberLabel.textAlignment = .right
        lineNumberLabel.backgroundColor = UIColor(ColorSystem.Editor.gutterBg)
        contentView.addSubview(lineNumberLabel)

        // Gutter separator
        gutterSeparator.backgroundColor = UIColor(ColorSystem.Editor.gutterBorder)
        contentView.addSubview(gutterSeparator)

        // Code container (clips the code content, positioned after gutter)
        codeContainer.clipsToBounds = true
        codeContainer.backgroundColor = .clear
        contentView.addSubview(codeContainer)

        // Code label (inside container, can be offset for horizontal scroll)
        codeLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        codeLabel.textColor = UIColor(ColorSystem.Syntax.plain)
        codeLabel.lineBreakMode = .byClipping
        codeContainer.addSubview(codeLabel)
    }

    func setHorizontalOffset(_ offset: CGFloat) {
        horizontalOffset = offset
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let height = contentView.bounds.height
        let width = contentView.bounds.width

        // Log cell dimensions (only first few to avoid spam)
        if let lineNum = Int(lineNumberLabel.text ?? "0"), lineNum <= 3 {
            AppLogger.log("[CodeLineCell] line \(lineNum) - contentView: \(width)x\(height), gutterWidth: \(gutterWidth), codeContainerWidth: \(width - gutterWidth)")
        }

        activeHighlight.frame = contentView.bounds

        // Fixed gutter (line numbers)
        lineNumberLabel.frame = CGRect(
            x: 0,
            y: 0,
            width: gutterWidth - 12,
            height: height
        )

        gutterSeparator.frame = CGRect(
            x: gutterWidth - 1,
            y: 0,
            width: 1,
            height: height
        )

        // Code container (clips content, fills area after gutter)
        codeContainer.frame = CGRect(
            x: gutterWidth,
            y: 0,
            width: width - gutterWidth,
            height: height
        )

        // Code label (offset for horizontal scroll, wide enough for content)
        codeLabel.frame = CGRect(
            x: 8 - horizontalOffset,
            y: 0,
            width: 10000,  // Large width for long lines
            height: height
        )
    }

    func configure(
        lineNumber: Int,
        content: String,
        gutterWidth: CGFloat,
        isActive: Bool,
        hasMatch: Bool,
        hasCurrentMatch: Bool,
        lineMatches: [SearchMatch],
        currentMatch: SearchMatch?,
        syntaxHighlighting: Bool,
        fileExtension: String?
    ) {
        self.gutterWidth = gutterWidth

        // Line number styling
        lineNumberLabel.text = "\(lineNumber)"
        lineNumberLabel.textColor = UIColor(
            hasCurrentMatch ? ColorSystem.primary :
            hasMatch ? ColorSystem.warning :
            isActive ? ColorSystem.Editor.lineNumberActive :
            ColorSystem.Editor.lineNumber
        )

        // Gutter background
        lineNumberLabel.backgroundColor = UIColor(
            isActive ? ColorSystem.Editor.activeLineBg : ColorSystem.Editor.gutterBg
        )

        // Active line highlight
        activeHighlight.isHidden = !isActive

        // Code content with optional syntax highlighting and search highlighting
        let monoFont = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        if !lineMatches.isEmpty {
            let attrText = buildHighlightedContent(
                content: content,
                lineMatches: lineMatches,
                currentMatch: currentMatch,
                syntaxHighlighting: syntaxHighlighting,
                fileExtension: fileExtension,
                font: monoFont
            )
            codeLabel.attributedText = attrText
        } else if syntaxHighlighting, let ext = fileExtension {
            let language = SyntaxHighlighter.detectLanguage(from: ext)
            if language != .plainText {
                // Use UIKit-specific highlighting that properly applies UIColor
                let nsAttr = SyntaxHighlighter.highlightForUIKit(line: content, language: language, font: monoFont)
                codeLabel.attributedText = nsAttr
            } else {
                codeLabel.attributedText = nil
                codeLabel.text = content.isEmpty ? " " : content
                codeLabel.textColor = UIColor(ColorSystem.Syntax.plain)
            }
        } else {
            codeLabel.attributedText = nil
            codeLabel.text = content.isEmpty ? " " : content
            codeLabel.textColor = UIColor(ColorSystem.Syntax.plain)
        }

        setNeedsLayout()
    }

    private func buildHighlightedContent(
        content: String,
        lineMatches: [SearchMatch],
        currentMatch: SearchMatch?,
        syntaxHighlighting: Bool,
        fileExtension: String?,
        font: UIFont
    ) -> NSAttributedString {
        // Start with syntax highlighted or plain text using UIKit-specific method
        let baseString: NSMutableAttributedString
        if syntaxHighlighting, let ext = fileExtension {
            let language = SyntaxHighlighter.detectLanguage(from: ext)
            if language != .plainText {
                // Use UIKit-specific highlighting that properly applies UIColor
                baseString = NSMutableAttributedString(attributedString: SyntaxHighlighter.highlightForUIKit(line: content, language: language, font: font))
            } else {
                baseString = NSMutableAttributedString(string: content.isEmpty ? " " : content, attributes: [
                    .font: font,
                    .foregroundColor: UIColor(ColorSystem.Syntax.plain)
                ])
            }
        } else {
            baseString = NSMutableAttributedString(string: content.isEmpty ? " " : content, attributes: [
                .font: font,
                .foregroundColor: UIColor(ColorSystem.Syntax.plain)
            ])
        }

        // Apply search match highlighting
        let sortedMatches = lineMatches.sorted { $0.startColumn < $1.startColumn }
        for match in sortedMatches {
            let isCurrent = match == currentMatch
            let range = NSRange(location: match.startColumn, length: match.endColumn - match.startColumn)

            guard range.location >= 0 && range.location + range.length <= baseString.length else { continue }

            baseString.addAttribute(.backgroundColor, value: UIColor(isCurrent ? ColorSystem.primary : ColorSystem.warning), range: range)
            baseString.addAttribute(.foregroundColor, value: UIColor(isCurrent ? ColorSystem.terminalBg : ColorSystem.textPrimary), range: range)
        }

        return baseString
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        lineNumberLabel.text = nil
        codeLabel.text = nil
        codeLabel.attributedText = nil
        activeHighlight.isHidden = true
    }
}
