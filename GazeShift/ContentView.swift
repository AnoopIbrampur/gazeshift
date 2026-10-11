import SwiftUI

private enum ScreenStyle {
    static let background = Color(red: 0.035, green: 0.065, blue: 0.09)
    static let surface = Color(red: 0.065, green: 0.11, blue: 0.14)
    static let accent = Color(red: 0.49, green: 0.91, blue: 0.80)
    static let secondary = Color(red: 0.65, green: 0.73, blue: 0.77)
    static let spacing: CGFloat = 24
    static let compactSpacing: CGFloat = 8
    static let cornerRadius: CGFloat = 24
    static let minimumViewportHeight: CGFloat = 180
}

struct ContentView: View {
    @Environment(\.displayScale) private var displayScale: CGFloat
    @State private var viewportSize: CGSize = .zero

    private var buildMarker: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return "BUILD MARKER MISSING"
        }
        return "P0-\(version)-\(build)"
    }

    private var runtimeLabel: String {
        #if targetEnvironment(simulator)
        "Simulator preview"
        #else
        "Device setup screen"
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ScreenStyle.spacing) {
            header
            Label(runtimeLabel, systemImage: "rectangle.inset.filled.and.person.filled")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ScreenStyle.accent)
            viewport
            viewportDetails
            footer
        }
        .padding(ScreenStyle.spacing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScreenStyle.background.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ScreenStyle.compactSpacing) {
            Text("GAZESHIFT / P0")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ScreenStyle.accent)
            Text("A new point of view.")
                .font(.largeTitle.weight(.semibold))
            Text("Experimental assistive vision")
                .font(.subheadline)
                .foregroundStyle(ScreenStyle.secondary)
        }
    }

    private var viewport: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: ScreenStyle.cornerRadius)
                .fill(ScreenStyle.surface)
                .overlay {
                    VStack(spacing: ScreenStyle.spacing) {
                        Image(systemName: "eye")
                            .font(.largeTitle)
                            .foregroundStyle(ScreenStyle.accent)
                        VStack(spacing: ScreenStyle.compactSpacing) {
                            Text("Camera view not started")
                                .font(.headline)
                            Text("No camera or eye tracking is active.")
                                .font(.subheadline)
                                .foregroundStyle(ScreenStyle.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(ScreenStyle.spacing)
                }
                .onAppear { viewportSize = geometry.size }
                .onChange(of: geometry.size) { _, size in viewportSize = size }
        }
        .frame(minHeight: ScreenStyle.minimumViewportHeight)
        .accessibilityIdentifier("measuredViewport")
    }

    private var viewportDetails: some View {
        HStack(alignment: .top) {
            metric("VIEWPORT", value: "\(Int(viewportSize.width)) × \(Int(viewportSize.height)) pt")
            Spacer()
            metric("DISPLAY SCALE", value: "\(displayScale.formatted())×")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: ScreenStyle.compactSpacing) {
            Text("Physical iPhone verification pending")
                .font(.footnote)
                .foregroundStyle(ScreenStyle.secondary)
            Text(buildMarker)
                .font(.caption.monospaced())
                .foregroundStyle(ScreenStyle.accent)
                .accessibilityIdentifier("buildMarker")
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: ScreenStyle.compactSpacing) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ScreenStyle.secondary)
            Text(value)
                .font(.subheadline.monospaced())
        }
    }
}
