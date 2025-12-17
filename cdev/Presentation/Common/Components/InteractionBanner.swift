import SwiftUI

/// Compact banner for pending interactions (permissions, questions)
struct InteractionBanner: View {
    let interaction: PendingInteraction
    let onApprove: () -> Void
    let onDeny: () -> Void
    let onAnswer: (String) -> Void

    @State private var answerText = ""

    var body: some View {
        VStack(spacing: Spacing.sm) {
            // Header
            HStack(spacing: Spacing.xs) {
                Image(systemName: iconName)
                    .font(.body)
                    .foregroundStyle(iconColor)

                Text(headerText)
                    .font(Typography.footnote)
                    .fontWeight(.semibold)

                Spacer()

                Text(interaction.timestamp.relativeString)
                    .font(Typography.caption2)
                    .foregroundStyle(.secondary)
            }

            // Description
            Text(interaction.description)
                .font(Typography.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)

            // Actions
            switch interaction.type {
            case .permission:
                PermissionActions(onApprove: onApprove, onDeny: onDeny)

            case .question:
                if let options = interaction.options, !options.isEmpty {
                    QuestionOptions(options: options, onSelect: onAnswer)
                } else {
                    QuestionInput(text: $answerText, onSubmit: {
                        onAnswer(answerText)
                        answerText = ""
                    })
                }
            }
        }
        .padding(Spacing.sm)
        .background(bannerBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
    }

    private var iconName: String {
        switch interaction.type {
        case .permission: return "lock.shield"
        case .question: return "questionmark.bubble"
        }
    }

    private var iconColor: Color {
        switch interaction.type {
        case .permission: return .warningOrange
        case .question: return .primaryBlue
        }
    }

    private var headerText: String {
        switch interaction.type {
        case .permission(let tool): return "Permission: \(tool)"
        case .question: return "Question"
        }
    }

    private var bannerBackground: Color {
        switch interaction.type {
        case .permission: return Color.warningOrange.opacity(0.15)
        case .question: return Color.primaryBlue.opacity(0.15)
        }
    }
}

// MARK: - Permission Actions

struct PermissionActions: View {
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: onDeny) {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "xmark")
                    Text("Deny")
                }
                .font(Typography.footnote)
                .fontWeight(.medium)
                .foregroundStyle(Color.errorRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xs)
                .background(Color.errorRed.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            }
            .pressEffect()

            Button(action: onApprove) {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "checkmark")
                    Text("Allow")
                }
                .font(Typography.footnote)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xs)
                .background(Color.accentGreen)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            }
            .pressEffect()
        }
    }
}

// MARK: - Question Options

struct QuestionOptions: View {
    let options: [QuestionOption]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: Spacing.xs) {
            ForEach(options) { option in
                Button {
                    onSelect(option.label)
                } label: {
                    HStack {
                        Text(option.label)
                            .font(Typography.footnote)
                            .fontWeight(.medium)

                        Spacer()

                        if let description = option.description {
                            Text(description)
                                .font(Typography.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                }
                .buttonStyle(.plain)
                .pressEffect()
            }
        }
    }
}

// MARK: - Question Input

struct QuestionInput: View {
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            TextField("Type your answer...", text: $text)
                .font(Typography.footnote)
                .textFieldStyle(.plain)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                .submitLabel(.send)
                .onSubmit(onSubmit)

            Button(action: onSubmit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(text.isBlank ? .secondary : Color.primaryBlue)
            }
            .disabled(text.isBlank)
        }
    }
}
