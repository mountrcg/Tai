import Charts
import SwiftUI

struct Sub5MinuteGlucoseSection: View {
    @ObservedObject var state: CGMSettings.StateModel
    @Binding var shouldDisplayHint: Bool
    @Binding var selectedVerboseHint: AnyView?
    @Binding var hintLabel: String?
    @State private var showScalingChart = false

    private var ratioDetail: String {
        String(
            localized: "With sub-5-minute loops an SMB can be issued every max(loop frequency, SMB interval) minutes. A ratio r per 5 minutes corresponds to 1 − (1 − r)^(period/5) per period. Ratios are never rescaled automatically — open the scaling chart and assign the values yourself."
        )
    }

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
                    label: AlgorithmSettingHints.smbDeliveryRatioFixedLabel,
                    explanation: String(
                        localized: "Share of the calculated SMB delivered per SMB. Set per loop/SMB period, not per 5 minutes; use the scaling chart to translate."
                    ),
                    decimal: $state.smbDeliveryRatio, key: "smbDeliveryRatio",
                    detail: ratioDetail
                )
                if state.smbDeliveryRatioBGrange != 0 {
                    input(
                        label: AlgorithmSettingHints.smbDeliveryRatioMinLabel,
                        explanation: AlgorithmSettingHints.smbDeliveryRatioMinMini,
                        decimal: $state.smbDeliveryRatioMin, key: "smbDeliveryRatioMin",
                        detail: ratioDetail
                    )
                    input(
                        label: AlgorithmSettingHints.smbDeliveryRatioMaxLabel,
                        explanation: AlgorithmSettingHints.smbDeliveryRatioMaxMini,
                        decimal: $state.smbDeliveryRatioMax, key: "smbDeliveryRatioMax",
                        detail: ratioDetail
                    )
                }
                Button {
                    showScalingChart = true
                } label: {
                    HStack {
                        Label("SMB Delivery Ratio Scaling", systemImage: "chart.xyaxis.line")
                        Spacer()
                        Text("\(Int(state.smbRatioPeriod.rounded())) min period")
                            .foregroundStyle(.secondary)
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
        .sheet(isPresented: $showScalingChart) {
            SmbDeliveryRatioScalingSheet(
                period: state.smbRatioPeriod,
                assigned: assignedRatios
            )
        }
    }

    private var assignedRatios: [SmbDeliveryRatioScalingSheet.AssignedRatio] {
        let toDouble = { (value: Decimal) in NSDecimalNumber(decimal: value).doubleValue }
        var result = [SmbDeliveryRatioScalingSheet.AssignedRatio(
            name: String(localized: "Fixed"), value: toDouble(state.smbDeliveryRatio)
        )]
        if state.smbDeliveryRatioBGrange != 0 {
            result.append(.init(name: String(localized: "Min"), value: toDouble(state.smbDeliveryRatioMin)))
            result.append(.init(name: String(localized: "Max"), value: toDouble(state.smbDeliveryRatioMax)))
        }
        return result
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

/// Reference relation between an SMB delivery ratio expressed per 5 minutes and the ratio that
/// delivers the same share of insulin per period when SMBs can be issued every `period` minutes:
/// r_period = 1 − (1 − r_5)^(period / 5). Display only: nothing is applied to the settings.
enum SmbDeliveryRatioScaling {
    static func ratio(forFiveMinute ratio5: Double, period: Double) -> Double {
        guard period > 0 else { return ratio5 }
        let r = min(max(ratio5, 0), 1)
        return 1 - pow(1 - r, period / 5)
    }

    /// Inverse: the 5-minute ratio a per-period ratio corresponds to. Ratios ≥ 100 % have no finite equivalent.
    static func fiveMinuteRatio(forPeriod ratioP: Double, period: Double) -> Double? {
        guard period > 0, ratioP >= 0, ratioP < 1 else { return nil }
        return 1 - pow(1 - ratioP, 5 / period)
    }
}

struct SmbDeliveryRatioScalingSheet: View {
    struct AssignedRatio: Identifiable {
        let name: String
        let value: Double
        var id: String { name }
    }

    /// max(loop frequency, SMB interval) in minutes.
    let period: Double
    let assigned: [AssignedRatio]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFiveMinute: Double?

    private let domain: ClosedRange<Double> = 0.1 ... 1.0
    private var periodLabel: String { period.formatted(.number.precision(.fractionLength(0 ... 1))) }

    private var curve: [(x: Double, y: Double)] {
        stride(from: domain.lowerBound, through: domain.upperBound + 1E-9, by: 0.01).map {
            (x: $0, y: SmbDeliveryRatioScaling.ratio(forFiveMinute: $0, period: period))
        }
    }

    /// Selection snapped to the 5 % picker grid.
    private var selection: (x: Double, y: Double)? {
        guard let raw = selectedFiveMinute else { return nil }
        let x = min(max((raw / 0.05).rounded() * 0.05, domain.lowerBound), domain.upperBound)
        return (x, SmbDeliveryRatioScaling.ratio(forFiveMinute: x, period: period))
    }

    private var assignedPoints: [(item: AssignedRatio, x: Double)] {
        assigned.compactMap { item in
            guard let x = SmbDeliveryRatioScaling.fiveMinuteRatio(forPeriod: item.value, period: period),
                  domain.contains(x) else { return nil }
            return (item, x)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        "SMBs can be issued every \(periodLabel) min — the larger of loop frequency and SMB interval. A delivery ratio applies per SMB, so the same ratio delivers more insulin per hour the shorter the period. The chart shows which per-period ratio matches a ratio you would use with 5-minute loops."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.chart)

                Section {
                    readout
                    chart
                        .frame(height: 260)
                        .padding(.vertical, 6)
                } footer: {
                    Text("Touch and drag (or hover) to read off a value. Dashed line: same value at 5 minutes.")
                }
                .listRowBackground(Color.chart)

                Section(header: Text("Reference")) {
                    ForEach([0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9], id: \.self) { r in
                        HStack {
                            Text("\(r.formatted(.percent.precision(.fractionLength(0)))) per 5 min")
                            Spacer()
                            Text(
                                "\(SmbDeliveryRatioScaling.ratio(forFiveMinute: r, period: period).formatted(.percent.precision(.fractionLength(0)))) per \(periodLabel) min"
                            )
                            .monospacedDigit()
                        }
                    }
                }
                .listRowBackground(Color.chart)

                if !assigned.isEmpty {
                    Section(header: Text("Your current values")) {
                        ForEach(assigned) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                if let x = SmbDeliveryRatioScaling.fiveMinuteRatio(forPeriod: item.value, period: period) {
                                    Text(
                                        "\(item.value.formatted(.percent.precision(.fractionLength(0)))) ≙ \(x.formatted(.percent.precision(.fractionLength(0)))) per 5 min"
                                    )
                                    .monospacedDigit()
                                } else {
                                    Text("\(item.value.formatted(.percent.precision(.fractionLength(0)))) (no 5-min equivalent)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.chart)
                }

                Section {
                    Text(
                        "r(\(periodLabel) min) = 1 − (1 − r(5 min))^(\(periodLabel)/5). Nominal cadence relation only; actual delivery also depends on max SMB, IOB limits and pump timing. Nothing is applied automatically — set the ratios yourself."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden)
            .background(appBackground)
            .navigationTitle("SMB Ratio Scaling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme
    private var appBackground: some View {
        colorScheme == .dark ? Color.bgDarkBlue.ignoresSafeArea() : Color.gray.opacity(0.1).ignoresSafeArea()
    }

    @ViewBuilder private var readout: some View {
        let shown = selection ?? (x: 0.5, y: SmbDeliveryRatioScaling.ratio(forFiveMinute: 0.5, period: period))
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading) {
                Text("5 min").font(.caption).foregroundStyle(.secondary)
                Text(shown.x.formatted(.percent.precision(.fractionLength(0)))).font(.title2.bold()).monospacedDigit()
            }
            Spacer()
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(periodLabel) min").font(.caption).foregroundStyle(.secondary)
                Text(shown.y.formatted(.percent.precision(.fractionLength(1)))).font(.title2.bold()).monospacedDigit()
                    .foregroundStyle(Color.insulin)
            }
        }
    }

    private var chart: some View {
        Chart {
            LineMark(
                x: .value("5 min", domain.lowerBound),
                y: .value("Period", domain.lowerBound),
                series: .value("Series", "5 min")
            )
            .foregroundStyle(Color.secondary)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            LineMark(
                x: .value("5 min", domain.upperBound),
                y: .value("Period", domain.upperBound),
                series: .value("Series", "5 min")
            )
            .foregroundStyle(Color.secondary)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ForEach(curve, id: \.x) { point in
                LineMark(x: .value("5 min", point.x), y: .value("Period", point.y), series: .value("Series", "period"))
                    .foregroundStyle(Color.insulin)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            ForEach(assignedPoints, id: \.item.id) { entry in
                PointMark(x: .value("5 min", entry.x), y: .value("Period", entry.item.value))
                    .foregroundStyle(Color.orange)
                    .symbolSize(50)
                    .annotation(position: .topLeading, spacing: 2) {
                        Text(entry.item.name).font(.caption2).foregroundStyle(.orange)
                    }
            }
            if let selection {
                RuleMark(x: .value("5 min", selection.x))
                    .foregroundStyle(Color.primary.opacity(0.35))
                RuleMark(y: .value("Period", selection.y))
                    .foregroundStyle(Color.primary.opacity(0.35))
                PointMark(x: .value("5 min", selection.x), y: .value("Period", selection.y))
                    .foregroundStyle(Color.insulin)
                    .symbolSize(90)
            }
        }
        .chartXScale(domain: 0 ... 1)
        .chartYScale(domain: 0 ... 1)
        .chartXAxis {
            AxisMarks(values: [0, 0.25, 0.5, 0.75, 1]) { value in
                AxisGridLine()
                AxisValueLabel { if let v = value.as(Double.self) { Text(v.formatted(.percent.precision(.fractionLength(0)))) } }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.25, 0.5, 0.75, 1]) { value in
                AxisGridLine()
                AxisValueLabel { if let v = value.as(Double.self) { Text(v.formatted(.percent.precision(.fractionLength(0)))) } }
            }
        }
        .chartXAxisLabel("per 5 min", alignment: .center)
        .chartYAxisLabel("per \(periodLabel) min", position: .leading)
        .chartXSelection(value: $selectedFiveMinute)
    }
}
