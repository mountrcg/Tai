import SwiftUI

struct Sub5MinuteGlucoseSection: View {
    @ObservedObject var state: CGMSettings.StateModel
    @Binding var shouldDisplayHint: Bool
    @Binding var selectedVerboseHint: AnyView?
    @Binding var hintLabel: String?

    var body: some View {
        Section(header: Text("Sub-5-Minute CGM")) {
            if state.isSuitableSource {
                input(
                    label: String(localized: "Use Sub-5-Minute Loops"),
                    explanation: String(
                        localized: "Default: OFF. Runs the loop on dense CGM readings more often than 5 minutes. AutoISF must be enabled separately."
                    ),
                    boolean: $state.enableSub5MinuteGlucose
                )
                input(
                    label: String(localized: "Loop Frequency"),
                    explanation: String(localized: "Default: 5 min. How often the loop calculates on dense readings. 1–10 min."),
                    decimal: $state.sub5MinuteLoopInterval, key: "sub5MinuteLoopInterval"
                )
                input(
                    label: String(localized: "SMB Interval"),
                    explanation: String(localized: "Default: 3 min. Minimum time between SMB micro-boluses."),
                    decimal: $state.smbInterval, key: "smbInterval"
                )
                input(
                    label: String(localized: "SMB Delivery Ratio"),
                    explanation: String(localized: "Suggestions are advisory. Apply only after reviewing the cadence change."),
                    decimal: $state.smbDeliveryRatio, key: "smbDeliveryRatio",
                    detail: String(
                        localized: "The suggestion uses M = max(loop frequency, SMB interval) and p = 1 − (1 − P)^(M1/M0), with the previous cadence and ratio as the baseline. It rounds down to the 5% picker grid and never increases the ratio. This is a nominal cadence heuristic, not a guarantee of actual insulin delivery."
                    )
                )
                if let ratio = state.suggestedRatio {
                    HStack {
                        Text(
                            "Suggested ratio: \(ratio.formatted(.wholePercent)) — keeps total SMB delivery per minute equal after the cadence change."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button("Apply") { state.applySuggestedRatio() }
                            .buttonStyle(.borderless)
                    }
                }
            } else {
                Text("Unavailable for this source. Select a CGM that supports trusted raw glucose observations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listRowBackground(Color.chart)
        .settingsSearchTarget(label: String(localized: "Sub-5-Minute CGM"))
        .onAppear { state.sub5MinuteSectionAppeared() }
    }

    private func input(
        label: String, explanation: String, boolean: Binding<Bool> = .constant(false),
        decimal: Binding<Decimal> = .constant(0), key: String? = nil, detail: String? = nil
    ) -> some View {
        SettingInputSection(
            decimalValue: decimal, booleanValue: boolean, shouldDisplayHint: $shouldDisplayHint,
            selectedVerboseHint: Binding(
                get: { selectedVerboseHint },
                set: {
                    selectedVerboseHint = $0.map { AnyView($0) }
                    hintLabel = label
                }
            ),
            units: state.units, type: key.map { .decimal($0) } ?? .boolean,
            label: label, miniHint: explanation,
            verboseHint: VStack(alignment: .leading, spacing: 10) {
                Text(explanation)
                if let detail { Text(detail) }
            }
        )
    }
}
