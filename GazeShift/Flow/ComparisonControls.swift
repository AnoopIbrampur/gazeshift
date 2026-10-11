import SwiftUI
import GazeShiftFlow

/// ANO-11 controls. Simulation starts OFF (normal Live). Turning the demo on selects Original first.
/// Mode changes never change render geometry; only the composition plan changes.
struct ComparisonControls: View {
    @Binding var mode: ViewMode
    let plan: CompositionPlan

    private var demoOn: Binding<Bool> {
        Binding(get: { mode != .live },
                set: { mode = $0 ? .comparison(.original) : .live })
    }

    private var comparison: Binding<ComparisonMode> {
        Binding(get: { if case let .comparison(selected) = mode { selected } else { .original } },
                set: { mode = .comparison($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ScreenStyle.spacing) {
            Toggle("Simulation", isOn: demoOn)
                .font(.body.weight(.semibold))
                .frame(minHeight: ScreenStyle.minimumControlHeight)
                .accessibilityIdentifier("demoComparisonToggle")
            if mode != .live {
                HStack(spacing: 0) {
                    comparisonButton("Original", selection: .original)
                    comparisonButton("Blur", selection: .simulatedBlur)
                    comparisonButton("Blur + Copy", selection: .simulatedBlurPlusCopy)
                }
                .background(ScreenStyle.background, in: Capsule())
                .overlay(Capsule().stroke(ScreenStyle.accent, lineWidth: 1))
                .accessibilityIdentifier("comparisonPicker")
            }
            if plan.isOriginalOnly, mode != .comparison(.original) {
                Text(plan.statusText).font(.subheadline).foregroundStyle(.red)
                    .accessibilityIdentifier("compositionStatus")
            }
        }
    }

    private func comparisonButton(_ title: String, selection: ComparisonMode) -> some View {
        Button { comparison.wrappedValue = selection } label: {
            Text(title).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: ScreenStyle.minimumControlHeight)
                .foregroundStyle(comparison.wrappedValue == selection ? .white : ScreenStyle.accent)
                .background(comparison.wrappedValue == selection ? ScreenStyle.accent : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(comparison.wrappedValue == selection ? .isSelected : [])
    }
}
