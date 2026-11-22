import SwiftUI
import Swinject

extension CGMSettings {
    /// Therapy Settings → CGM and Loop Intervals: sub-5-minute loop configuration for the selected CGM.
    struct LoopIntervalsRootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var shouldDisplayHint = false
        @State private var hintDetent = PresentationDetent.large
        @State private var selectedVerboseHint: AnyView?
        @State private var hintLabel: String?

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                Section(header: Text("Current CGM")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.cgmCurrent.displayName)
                        if !state.cgmCurrent.subtitle.isEmpty {
                            Text(state.cgmCurrent.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !state.isSuitableSource {
                        Text(
                            "This CGM does not provide readings more often than every 5 minutes. Trio loops on its regular 5-minute cadence; nothing needs to be configured here."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.chart)

                if state.isSuitableSource {
                    Sub5MinuteGlucoseSection(
                        state: state, shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: $selectedVerboseHint, hintLabel: $hintLabel
                    )
                }
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("CGM and Loop Intervals")
            .navigationBarTitleDisplayMode(.automatic)
            .settingsHighlightScroll()
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
        }
    }
}
