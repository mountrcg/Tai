import SwiftUI

struct SmbDeliveryRatioSuggestionSheet: View {
    @ObservedObject var review: SmbDeliveryRatioReview
    let pending: SmbDeliveryRatioReview.Pending
    @State private var selected: Set<SmbDeliveryRatioSuggestion.Field> = []
    @State private var values: [SmbDeliveryRatioSuggestion.Field: Decimal] = [:]
    @State private var zoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    private var selectedValues: [SmbDeliveryRatioSuggestion.Field: Decimal] {
        values.filter { selected.contains($0.key) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        String(
                            localized: "Suggested reference interval: \(pending.proposed.sub5MinuteLoopInterval.description) min, compared with 5 min."
                        )
                    )
                    Text(
                        String(
                            localized: "This is a configuration-review heuristic, not a prescription, clinical equivalence, or an insulin-per-hour guarantee. Actual delivery still depends on glucose, SMB timing, caps, and pump increments."
                        )
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }.listRowBackground(Color.chart)
                ForEach(pending.fields) { field in
                    Section(header: Text(field.label)) {
                        Text(String(localized: "Current: \(pending.current(field).formatted(.upToTwoDecimalPercent))"))
                        if case let .suggestion(suggested, limited) = pending.suggestion(field) {
                            Toggle(String(localized: "Apply This Ratio"), isOn: Binding(
                                get: { selected.contains(field) },
                                set: { if $0 { selected.insert(field) } else { selected.remove(field) } }
                            ))
                            Picker(String(localized: "Suggested Ratio"), selection: Binding(
                                get: { values[field] ?? suggested }, set: { values[field] = $0 }
                            )) {
                                ForEach(pickerValues(field), id: \.self) { value in
                                    Text(value.formatted(.upToTwoDecimalPercent)).tag(value)
                                }
                            }
                            .accessibilityLabel(field.label + ", " + String(localized: "Suggested Ratio"))
                            if limited {
                                Text(
                                    String(
                                        localized: "The picker minimum limits this reduction; the formula result is below the available range."
                                    )
                                )
                                .font(.footnote).foregroundStyle(.orange)
                            }
                        } else {
                            Text(
                                String(
                                    localized: "No actionable suggestion. Ratios at or above 100% are outside this graph's reduction domain; invalid imported values require manual correction."
                                )
                            )
                            .font(.footnote).foregroundStyle(.secondary)
                        }
                    }.listRowBackground(Color.chart)
                }
                Section {
                    if pending.fields.count > 1 {
                        Text(
                            String(
                                localized: "The variable ramp is active. Full Loop can use max(fixed, ramp). Selecting only the fixed ratio leaves the ramp unchanged. Minimum must not exceed maximum."
                            )
                        )
                    }
                    Text(
                        String(
                            localized: "Small ratios may yield zero SMB after pump-increment flooring. No cap, BG range, SMB interval, or pump increment is changed."
                        )
                    )
                    ScrollView([.horizontal, .vertical]) {
                        Image("RatioEquivalents")
                            .resizable().scaledToFit().frame(width: 320 * min(4, max(1, zoom * magnification)))
                            .accessibilityLabel(
                                String(localized: "Equivalent delivery shares for one-minute and five-minute reference intervals")
                            )
                            .gesture(
                                MagnificationGesture()
                                    .updating($magnification) { value, state, _ in state = value }
                                    .onEnded { zoom = min(4, max(1, zoom * $0)) }
                            )
                    }.frame(height: 260)
                    Text(
                        String(
                            localized: "This static 2024 graph shows only L = 1 minute. For other intervals, suggestions use p = 1 − (1 − P)^(L/5); this image is not a lookup table for those intervals. Pinch to zoom."
                        )
                    )
                }.font(.footnote).foregroundStyle(.secondary).listRowBackground(Color.chart)
                Section {
                    Button(String(localized: "Apply Selected Suggestions")) {
                        review.resolve(pending.id, as: .apply, values: selectedValues)
                    }.disabled(!review.canApply(pending, values: selectedValues))
                    Button(String(localized: "Keep My Values")) { review.resolve(pending.id, as: .keep) }
                    Button(String(localized: "Cancel Change"), role: .cancel) { review.resolve(pending.id, as: .cancel) }
                }.buttonStyle(.borderless).listRowBackground(Color.chart)
            }
            .listSectionSpacing(sectionSpacing)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle(String(localized: "Review SMB Delivery Ratios"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            for field in pending.fields {
                if case let .suggestion(value, _) = pending.suggestion(field) { values[field] = value }
            }
        }
    }

    private func pickerValues(_ field: SmbDeliveryRatioSuggestion.Field) -> [Decimal] {
        let key: String
        switch field {
        case .fixed: key = "smbDeliveryRatio"
        case .minimum: key = "smbDeliveryRatioMin"
        case .maximum: key = "smbDeliveryRatioMax"
        }
        guard let setting = PickerSettingsProvider.shared.pickerSetting(for: key) else { return [] }
        return PickerSettingsProvider.shared.generatePickerValues(from: setting, units: .mgdL)
            .filter { $0 <= pending.current(field) }
    }
}

private extension SmbDeliveryRatioSuggestion.Field {
    var label: String {
        switch self {
        case .fixed: return String(localized: "Fixed SMB Delivery Ratio")
        case .minimum: return String(localized: "Minimum SMB Delivery Ratio")
        case .maximum: return String(localized: "Maximum SMB Delivery Ratio")
        }
    }
}
