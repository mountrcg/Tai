import Charts
import SwiftUI

struct Sub5MinuteGlucoseSection: View {
    @ObservedObject var state: CGMSettings.StateModel
    @Binding var shouldDisplayHint: Bool
    @Binding var selectedVerboseHint: AnyView?
    @Binding var hintLabel: String?

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
                        localized: "Default: OFF. Runs the loop on every dense CGM reading, more often than every 5 minutes. The loop frequency follows the CGM interval detected from the readings. AutoISF must be enabled separately."
                    ),
                    boolean: Binding(get: { state.enableSub5MinuteGlucose }, set: { state.setSub5MinuteGlucose($0) })
                )
                HStack {
                    Text("Loop Frequency")
                    Spacer()
                    Group {
                        if !state.enableSub5MinuteGlucose {
                            Text("5 min")
                        } else if let minutes = state.detectedCGMMinutes {
                            Text("\(minutes) min (detected)")
                        } else {
                            Text("Detecting…")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                input(
                    label: String(localized: "SMB Interval"),
                    explanation: String(localized: "Default: 3 min. Minimum time between SMB micro-boluses."),
                    decimal: $state.smbInterval, key: "smbInterval"
                )
                NavigationLink {
                    SmbDeliveryRatioScalingPage(period: state.smbRatioPeriod, handles: ratioHandles)
                } label: {
                    HStack {
                        Label("SMB Delivery Ratio Scaling", systemImage: "chart.xyaxis.line")
                        Spacer()
                        Text(
                            state.detectedCGMMinutes == nil
                                ? "\(Int(state.smbRatioPeriod.rounded())) min period (1-min CGM assumed)"
                                : "\(Int(state.smbRatioPeriod.rounded())) min period"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
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
            }
        }
        .listRowBackground(Color.chart)
        .settingsSearchTarget(label: String(localized: "Sub-5-Minute CGM"))
        .onAppear { state.sub5MinuteSectionAppeared() }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            state.refreshDetectedCGMMinutes()
        }
    }

    private var ratioHandles: [SmbDeliveryRatioScalingPage.Handle] {
        var result = [SmbDeliveryRatioScalingPage.Handle(
            name: String(localized: "Fix"), value: $state.smbDeliveryRatio, range: 0.1 ... 1.0
        )]
        if state.smbDeliveryRatioBGrange != 0 {
            result.append(.init(name: String(localized: "Min"), value: $state.smbDeliveryRatioMin, range: 0.1 ... 1.0))
            result.append(.init(name: String(localized: "Max"), value: $state.smbDeliveryRatioMax, range: 0.1 ... 1.0))
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

struct SmbDeliveryRatioScalingPage: View {
    /// A ratio setting that can be dragged along the curve. `value` is the per-period setting.
    struct Handle: Identifiable {
        let name: String
        let value: Binding<Decimal>
        /// Draggable range of the setting (the curve ends at 100 %).
        let range: ClosedRange<Double>
        var id: String { name }
    }

    /// max(loop frequency, SMB interval) in minutes.
    let period: Double
    let handles: [Handle]

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var shouldDisplayHint = false
    @State private var hintDetent = PresentationDetent.large
    @Environment(\.colorScheme) private var colorScheme
    /// Hovered/scrubbed per-period ratio when no handle is being dragged.
    @State private var scrubRatio: Double?
    /// Handle currently being dragged (or last dragged), shown in the readout.
    @State private var activeHandleID: String?
    @State private var dragHandleID: String?
    @State private var gestureActive = false
    /// Dragged values not yet confirmed, keyed by handle id. Settings change only on Confirm.
    @State private var draft: [String: Decimal] = [:]

    private func draftDecimal(_ handle: Handle) -> Decimal { draft[handle.id] ?? handle.value.wrappedValue }
    private func value(of handle: Handle) -> Double { NSDecimalNumber(decimal: draftDecimal(handle)).doubleValue }
    private func isChanged(_ handle: Handle) -> Bool { draftDecimal(handle) != handle.value.wrappedValue }
    private var hasChanges: Bool { handles.contains(where: isChanged) }

    private func confirm() {
        for handle in handles where isChanged(handle) {
            handle.value.wrappedValue = draftDecimal(handle)
        }
        draft = [:]
        dismiss()
    }

    private let domain: ClosedRange<Double> = 0.1 ... 1.0
    private let grabRadius: CGFloat = 36
    private var periodLabel: String { period.formatted(.number.precision(.fractionLength(0 ... 1))) }

    private func fiveMinute(_ p: Double) -> Double {
        SmbDeliveryRatioScaling.fiveMinuteRatio(forPeriod: p, period: period) ?? 1
    }

    private func snapped(_ raw: Double, to range: ClosedRange<Double>) -> Double {
        min(max((raw / 0.05).rounded() * 0.05, range.lowerBound), range.upperBound)
    }

    /// Curve points: `five` = ratio per 5 min (y axis), `period` = ratio per period (x axis).
    private var curve: [(five: Double, period: Double)] {
        stride(from: domain.lowerBound, through: domain.upperBound + 1E-9, by: 0.01).map {
            (five: $0, period: SmbDeliveryRatioScaling.ratio(forFiveMinute: $0, period: period))
        }
    }

    private var readoutValue: (label: String?, period: Double) {
        if let id = dragHandleID ?? (scrubRatio == nil ? activeHandleID : nil),
           let handle = handles.first(where: { $0.id == id })
        {
            return (handle.name, value(of: handle))
        }
        if let scrubRatio { return (nil, snapped(scrubRatio, to: 0.05 ... 1.0)) }
        return (handles.first?.name, handles.first.map(value(of:)) ?? 0.5)
    }

    var body: some View {
        List {
            Section {
                readout
                chart
                    .frame(height: 280)
                    .padding(.vertical, 6)
            }
            .listRowBackground(Color.chart)

            Section {
                ForEach(handles) { handle in
                    HStack {
                        Text(handle.name)
                        if isChanged(handle) {
                            Text("(was \(handle.value.wrappedValue.formatted(.percent.precision(.fractionLength(0)))))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if value(of: handle) < 1 {
                            Text(
                                "\(value(of: handle).formatted(.percent.precision(.fractionLength(0)))) = \(fiveMinute(value(of: handle)).formatted(.percent.precision(.fractionLength(0)))) per 5 min"
                            )
                            .monospacedDigit()
                        } else {
                            Text("\(value(of: handle).formatted(.percent.precision(.fractionLength(0)))) (no 5-min equivalent)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    confirm()
                } label: {
                    Text("Confirm")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges)
            }
            .listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appBackground)
        .navigationTitle("SMB Ratio Scaling")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shouldDisplayHint = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .accessibilityLabel(Text("More information"))
                }
            }
        }
        .sheet(isPresented: $shouldDisplayHint) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint,
                hintLabel: String(localized: "SMB Delivery Ratio Scaling"),
                hintText: VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "SMBs can be issued every \(periodLabel) min — the larger of loop frequency and SMB interval. A delivery ratio applies per SMB, so the same ratio delivers more insulin per hour the shorter the period."
                    )
                    Text(
                        "The x axis is the ratio you set at this period, the y axis its equivalent with 5-minute loops. The dashed line marks the same value at 5 minutes."
                    )
                    Text(
                        "Drag \(handles.map(\.name).formatted(.list(type: .and))) along the curve to choose a ratio (5 % steps), then tap Confirm to save it. Going back without confirming discards the change. Touch elsewhere on the chart (or hover) to read off any value."
                    )
                    Text(
                        "r(\(periodLabel) min) = 1 − (1 − r(5 min))^(\(periodLabel)/5). Nominal cadence relation only; actual delivery also depends on max SMB, IOB limits and pump timing."
                    )
                },
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
    }

    private var appBackground: some View {
        appState.trioBackgroundColor(for: colorScheme)
    }

    @ViewBuilder private var readout: some View {
        let shown = readoutValue
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading) {
                Text([shown.label, "\(periodLabel) min"].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                Text(shown.period.formatted(.percent.precision(.fractionLength(0))))
                    .font(.title2.bold()).monospacedDigit()
                    .foregroundStyle(shown.label == nil ? Color.insulin : Color.orange)
            }
            Spacer()
            Image(systemName: "equal").foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing) {
                Text("5 min").font(.caption).foregroundStyle(.secondary)
                Text(fiveMinute(shown.period).formatted(.percent.precision(.fractionLength(1))))
                    .font(.title2.bold()).monospacedDigit()
            }
        }
    }

    private var chart: some View {
        Chart {
            LineMark(
                x: .value("Period", domain.lowerBound),
                y: .value("5 min", domain.lowerBound),
                series: .value("Series", "5 min")
            )
            .foregroundStyle(Color.secondary)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            LineMark(
                x: .value("Period", domain.upperBound),
                y: .value("5 min", domain.upperBound),
                series: .value("Series", "5 min")
            )
            .foregroundStyle(Color.secondary)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ForEach(curve, id: \.five) { point in
                LineMark(x: .value("Period", point.period), y: .value("5 min", point.five), series: .value("Series", "period"))
                    .foregroundStyle(Color.insulin)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            if dragHandleID == nil, let scrubRatio {
                let p = snapped(scrubRatio, to: 0.05 ... 1.0)
                RuleMark(x: .value("Period", p))
                    .foregroundStyle(Color.primary.opacity(0.35))
                RuleMark(y: .value("5 min", fiveMinute(p)))
                    .foregroundStyle(Color.primary.opacity(0.35))
                PointMark(x: .value("Period", p), y: .value("5 min", fiveMinute(p)))
                    .foregroundStyle(Color.insulin)
                    .symbolSize(70)
            }
            ForEach(handles) { handle in
                let p = min(value(of: handle), 1)
                let isActive = handle.id == dragHandleID
                PointMark(x: .value("Period", p), y: .value("5 min", fiveMinute(p)))
                    .foregroundStyle(Color.orange)
                    .symbolSize(isActive ? 260 : 150)
                    .annotation(position: .topLeading, spacing: 4) {
                        Text(handle.name).font(.caption.bold()).foregroundStyle(.orange)
                    }
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
        .chartXAxisLabel("per \(periodLabel) min (setting)", alignment: .center)
        .chartYAxisLabel("per 5 min", position: .leading)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in handleDrag(drag, proxy: proxy, geo: geo) }
                            .onEnded { _ in
                                dragHandleID = nil
                                scrubRatio = nil
                                gestureActive = false
                            }
                    )
                    .onContinuousHover { phase in
                        guard !gestureActive else { return }
                        switch phase {
                        case let .active(location):
                            scrubRatio = ratio(atX: location.x, proxy: proxy, geo: geo)
                        case .ended:
                            scrubRatio = nil
                        }
                    }
            }
        }
    }

    private func ratio(atX x: CGFloat, proxy: ChartProxy, geo: GeometryProxy) -> Double? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        return proxy.value(atX: x - geo[plotFrame].minX, as: Double.self)
    }

    private func handleDrag(_ drag: DragGesture.Value, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geo[plotFrame].origin
        if !gestureActive {
            gestureActive = true
            // Gesture start: grab the nearest handle within reach, otherwise scrub.
            let start = CGPoint(x: drag.startLocation.x - origin.x, y: drag.startLocation.y - origin.y)
            let nearest = handles.compactMap { handle -> (String, CGFloat)? in
                let p = min(value(of: handle), 1)
                guard let position = proxy.position(for: (x: p, y: fiveMinute(p))) else { return nil }
                return (handle.id, hypot(position.x - start.x, position.y - start.y))
            }.min { $0.1 < $1.1 }
            if let nearest, nearest.1 <= grabRadius {
                dragHandleID = nearest.0
                activeHandleID = nearest.0
            }
        }
        guard let raw = proxy.value(atX: drag.location.x - origin.x, as: Double.self) else { return }
        if let id = dragHandleID, let handle = handles.first(where: { $0.id == id }) {
            let value = snapped(raw, to: handle.range)
            let decimal = Decimal(Int((value * 20).rounded())) / 20
            if draftDecimal(handle) != decimal {
                draft[handle.id] = decimal
                UISelectionFeedbackGenerator().selectionChanged()
            }
        } else {
            scrubRatio = raw
        }
    }
}
