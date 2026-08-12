import SwiftUI

enum SettingsHelpTone {
    case secondary
    case tertiary
    case warning
    case error
}

struct SettingsHelpText: View {
    let text: String
    var tone: SettingsHelpTone = .secondary

    init(_ text: String, tone: SettingsHelpTone = .secondary) {
        self.text = text
        self.tone = tone
    }

    @ViewBuilder
    var body: some View {
        switch tone {
        case .secondary:
            label.foregroundStyle(.secondary)
        case .tertiary:
            label.foregroundStyle(.tertiary)
        case .warning:
            label.foregroundStyle(.orange)
        case .error:
            label.foregroundStyle(.red)
        }
    }

    private var label: some View {
        Text(text)
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double?

    init(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double? = nil
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
        }
    }
}
