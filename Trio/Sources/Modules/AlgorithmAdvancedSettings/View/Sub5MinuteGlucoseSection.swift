import SwiftUI

struct Sub5MinuteGlucoseSection: View {
    @ObservedObject var review: SmbDeliveryRatioReview
    @ObservedObject var state: AlgorithmAdvancedSettings.StateModel
    @State private var showHint = false
    @State private var hint: AnyView?
    @State private var hintDetent = PresentationDetent.large

    private var cadence: GlucoseCadence { state.glucoseStorage.observationContext?.cadence ?? .legacy }
    private var trusted: Bool {
        let settings = state.settingsManager.settings
        return settings.cgm == .plugin &&
            CGMCatalogEntry.supportsRawGlucoseObservations(identifier: settings.cgmPluginIdentifier)
    }

    private func binding<T>(_ key: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { review.preferences[keyPath: key] }, set: { review.change(key, to: $0) })
    }

    var body: some View {
        Group {
            input(
                label: String(localized: "Sub-5-minute CGM"),
                explanation: String(
                    localized: "Default: OFF. Retain trusted dense CGM readings and enable dense processing. AutoISF must be enabled separately. Detection alone never enables this setting."
                ),
                boolean: binding(\.enableSub5MinuteGlucose), header: String(localized: "Sub-5-minute CGM")
            )
            Section {
                Text(
                    trusted ? String(localized: "Trusted source; dense cadence must also qualify.") :
                        String(localized: "Unavailable for this source. Relayed readings do not establish trust.")
                )
                Text(
                    cadence.isDense ? String(localized: "Sub-5-minute cadence detected.") :
                        String(localized: "No qualified dense cadence is currently available.")
                )
                if !state.settingsManager.settings.smoothGlucose || !review.preferences.autoisf {
                    Text(String(localized: "Smoothed parabola is inactive until glucose smoothing and AutoISF are enabled."))
                }
                Text(
                    String(
                        localized: "Existing SMB interval (read only): \(state.scope.preferences.smbInterval.description) min."
                    )
                )
                if review.needsReview {
                    Button(String(localized: "Review SMB Delivery Ratios")) { review.reviewCurrent() }
                        .buttonStyle(.borderless)
                    Text(
                        String(
                            localized: "This configuration has not been reviewed here. Imported or activated profiles never apply suggestions automatically."
                        )
                    )
                }
                if review.staleReview {
                    Text(
                        String(
                            localized: "Settings, profile, or source changed. The pending change was discarded; review the current values again."
                        )
                    )
                    .foregroundStyle(.orange)
                }
            }
            .settingsSearchTarget(label: String(localized: "Review SMB Delivery Ratios"))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .listRowBackground(Color.chart)

            input(
                label: String(localized: "Loop Interval Reference"),
                explanation: String(
                    localized: "Default: 5 minutes. Used only for the delivery-ratio suggestion. This stored reference does not schedule loops or change the existing SMB interval."
                ),
                decimal: binding(\.sub5MinuteLoopInterval), key: "sub5MinuteLoopInterval"
            )
            input(
                label: String(localized: "Parabola on Smoothed Glucose"),
                explanation: String(
                    localized: "Default: OFF. Requires trusted dense readings, glucose smoothing and AutoISF. Otherwise the raw fit remains in use."
                ),
                boolean: binding(\.autoISFParabolaSmoothed)
            )
            input(
                label: String(localized: "Automatic Parabola Minimum"),
                explanation: String(
                    localized: "Default: Automatic. Uses 10 minutes for a qualified cadence below 90 seconds, otherwise 15 minutes. A manual minimum may be 5–20 minutes."
                ),
                boolean: Binding(
                    get: { review.preferences.autoISFParabolaMinMinutes == nil },
                    set: { review.change(\.autoISFParabolaMinMinutes, to: $0 ? nil : cadence.parabolaMinimum(override: nil)) }
                )
            )
            if review.preferences.autoISFParabolaMinMinutes != nil {
                input(
                    label: String(localized: "Shortest Parabola Duration"),
                    explanation: String(localized: "Default: Automatic. This minimum affects the dense AutoISF fit only."),
                    decimal: Binding(
                        get: { review.preferences.autoISFParabolaMinMinutes ?? cadence.parabolaMinimum(override: nil) },
                        set: { review.change(\.autoISFParabolaMinMinutes, to: $0) }
                    ), key: "autoISFParabolaMinMinutes"
                )
            } else {
                Section {
                    Text(
                        String(
                            localized: "Automatic parabola minimum: \(cadence.parabolaMinimum(override: nil).description) min."
                        )
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }.listRowBackground(Color.chart)
            }
        }
        .onAppear { review.refresh() }
        .sheet(item: $review.pending, onDismiss: { review.pending = nil }) { pending in
            SmbDeliveryRatioSuggestionSheet(review: review, pending: pending)
        }
        .sheet(isPresented: $showHint) {
            SettingInputHintView(
                hintDetent: $hintDetent, shouldDisplayHint: $showHint,
                hintLabel: String(localized: "Sub-5-minute CGM"), hintText: hint ?? AnyView(EmptyView()),
                sheetTitle: String(localized: "Help")
            )
        }
    }

    private func input(
        label: String, explanation: String, decimal: Binding<Decimal> = .constant(0),
        boolean: Binding<Bool> = .constant(false), key: String? = nil, header: String? = nil
    ) -> some View {
        SettingInputSection(
            decimalValue: decimal, booleanValue: boolean, shouldDisplayHint: $showHint,
            selectedVerboseHint: Binding(get: { hint }, set: { hint = $0.map { AnyView($0) } }), units: state.units,
            type: key.map { .decimal($0) } ?? .boolean,
            label: label, miniHint: explanation,
            verboseHint: VStack(alignment: .leading) { Text(explanation) }, headerText: header
        )
    }
}
