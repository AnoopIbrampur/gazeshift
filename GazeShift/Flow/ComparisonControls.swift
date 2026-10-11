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
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Demo comparison", isOn: demoOn).accessibilityIdentifier("demoComparisonToggle")
            if mode != .live {
                Picker("View", selection: comparison) {
                    ForEach(ComparisonMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("comparisonPicker")
            }
            Text(plan.statusText).font(.subheadline.weight(.medium)).accessibilityIdentifier("compositionStatus")
            if let label = plan.simulationLabel {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    .accessibilityIdentifier("simulationLabel")
            }
        }
    }
}
