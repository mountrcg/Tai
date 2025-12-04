import Charts
import SwiftUI
import Swinject

extension BasalProfileEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State private var refreshUI = UUID()
        @State private var now = Date()
        @State private var shouldDisplayHint: Bool = false
        @State private var hintDetent = PresentationDetent.fraction(0.9)
        @Namespace private var bottomID

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var rateFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        // Chart for visualizing basal profile
        private var basalProfileChart: some View {
            Chart {
                ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                    let displayValue = state.rateValues[item.rateIndex]

                    // Check if this rate was rounded
                    let isRounded = state.roundedRateIndices.contains(index)

                    let startDate = Calendar.current
                        .startOfDay(for: now)
                        .addingTimeInterval(state.timeValues[item.timeIndex])

                    var offset: TimeInterval {
                        if state.items.count > index + 1 {
                            return state.timeValues[state.items[index + 1].timeIndex]
                        } else {
                            return state.timeValues.last! + 30 * 60
                        }
                    }

                    let endDate = Calendar.current.startOfDay(for: now).addingTimeInterval(offset)

                    RectangleMark(
                        xStart: .value("start", startDate),
                        xEnd: .value("end", endDate),
                        yStart: .value("rate-start", displayValue),
                        yEnd: .value("rate-end", 0)
                    ).foregroundStyle(
                        .linearGradient(
                            colors: isRounded ? [
                                Color.orange.opacity(0.6),
                                Color.orange.opacity(0.1)
                            ] : [
                                Color.purple.opacity(0.6),
                                Color.purple.opacity(0.1)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    ).alignsMarkStylesWithPlotArea()

                    LineMark(x: .value("End Date", startDate), y: .value("Rate", displayValue))
                        .lineStyle(.init(lineWidth: isRounded ? 2 : 1))
                        .foregroundStyle(isRounded ? Color.orange : Color.purple)

                    LineMark(x: .value("Start Date", endDate), y: .value("Rate", displayValue))
                        .lineStyle(.init(lineWidth: isRounded ? 2 : 1))
                        .foregroundStyle(isRounded ? Color.orange : Color.purple)
                }
            }
            .id(refreshUI) // Force chart update
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour())
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .chartXScale(
                domain: Calendar.current.startOfDay(for: now) ... Calendar.current.startOfDay(for: now)
                    .addingTimeInterval(60 * 60 * 24)
            )
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel()
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
        }

        var saveButton: some View {
            ZStack {
                let shouldDisableButton = state.syncInProgress || state.items.isEmpty || !state.hasChanges

                Rectangle()
                    .frame(width: UIScreen.main.bounds.width, height: 65)
                    .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                    .background(.thinMaterial)
                    .opacity(0.8)
                    .clipShape(Rectangle())

                Group {
                    HStack {
                        Button(action: {
                            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                            impactHeavy.impactOccurred()
                            state.save()
                        }, label: {
                            HStack {
                                if state.syncInProgress {
                                    ProgressView().padding(.trailing, 10)
                                }
                                Text(state.syncInProgress ? "Saving..." : "Save")
                            }
                            .frame(width: UIScreen.main.bounds.width * 0.9, alignment: .center)
                            .padding(10)
                        })
                            .frame(width: UIScreen.main.bounds.width * 0.9, height: 40, alignment: .center)
                            .disabled(shouldDisableButton)
                            .background(shouldDisableButton ? Color(.systemGray4) : Color(.systemBlue))
                            .tint(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(5)
            }
        }

        var fullScheduleWarning: some View {
            VStack {
                Text(
                    "Basal profile covers 24 hours. You cannot add more rates. Please remove or adjust existing rates to make space."
                ).bold()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.tabBar)
            .clipShape(
                .rect(
                    topLeadingRadius: 10,
                    bottomLeadingRadius: 10,
                    bottomTrailingRadius: 10,
                    topTrailingRadius: 10
                )
            )
        }

        var totalBasalRow: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Total")
                        .bold()

                    Spacer()

                    HStack {
                        Text(rateFormatter.string(from: state.total as NSNumber) ?? "0")
                        Text("U/day")
                            .foregroundStyle(Color.secondary)
                    }
                    .id(refreshUI)
                }
            }
            .padding()
            .background(Color.chart.opacity(0.65))
            .cornerRadius(10)
            .padding(.horizontal)
            .id(bottomID)
        }

        var body: some View {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack {
                            VStack(alignment: .leading, spacing: 0) {
                                if state.concentration != 1 || state.roundingHint {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                            Image(systemName: "info.circle.fill")
                                                .font(.title2)
                                                .foregroundStyle(.blue)
                                            Text("Concentration Information")
                                                .font(.headline)
                                            Spacer()
                                        }
                                        Grid(alignment: .trailing) {
                                            GridRow {
                                                Text("Insulin Concentration:").foregroundStyle(Color.secondary)
                                                    .gridColumnAlignment(.leading)
                                                Text("U\(Int(truncating: NSDecimalNumber(decimal: state.concentration * 100)))")
                                                Image(systemName: "questionmark.circle")
                                                    .foregroundStyle(Color.tabBar)
                                                    .onTapGesture {
                                                        shouldDisplayHint = true
                                                    }
                                            }
                                            GridRow {
                                                Text("Pump supported increment:").foregroundStyle(Color.secondary)
                                                    .gridColumnAlignment(.leading)
                                                Text("\(rateFormatter.string(from: state.pumpIncrement * 10 as NSNumber) ?? "0")")
                                                Text("μL/hr").foregroundStyle(Color.secondary)
                                            }
                                            Divider()
                                            GridRow {
                                                Text("Available basal increment:")
                                                    .gridColumnAlignment(.leading)
                                                Text("\(rateFormatter.string(from: state.basalIncrement as NSNumber) ?? "0")")
                                                Text("U/hr").foregroundStyle(Color.secondary)
                                            }.bold()
                                        }

                                        if state.roundingHint {
                                            Divider()
                                                .padding(.vertical, 4)

                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .foregroundStyle(.orange)
                                                    .font(.caption)

                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("Rates Adjusted")
                                                        .bold()
                                                        .foregroundStyle(.orange)

                                                    Text(
                                                        "Some basal rates have been rounded to match available pump increments for U\(Int(state.concentration * 100)) insulin. Highlighted entries show adjusted values. Please REVIEW and Save."
                                                    )
                                                    .foregroundStyle(.secondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                }
                                            }
                                            .padding(.vertical, 4)
                                        }

                                        Text(
                                            "Values shown are adjusted for your insulin concentration. The pump receives the correct physical delivery rates."
                                        )
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding()
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(10)
                                    .padding(.horizontal)
                                    .padding(.top)
                                }

                                if !state.canAdd {
                                    VStack {
                                        Text(
                                            "Basal profile covers 24 hours. You cannot add more rates. Please remove or adjust existing rates to make space."
                                        ).bold()
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                                    .background(Color.tabBar)
                                    .clipShape(
                                        .rect(
                                            topLeadingRadius: 10,
                                            bottomLeadingRadius: 10,
                                            bottomTrailingRadius: 10,
                                            topTrailingRadius: 10
                                        )
                                    )
                                    .padding(.horizontal)
                                    .padding(.top)
                                }

                                // Chart visualization
                                basalProfileChart
                                    .frame(height: 180)
                                    .padding()
                                    .background(Color.chart.opacity(0.65))
                                    .clipShape(
                                        .rect(
                                            topLeadingRadius: 10,
                                            bottomLeadingRadius: 0,
                                            bottomTrailingRadius: 0,
                                            topTrailingRadius: 10
                                        )
                                    )
                                    .padding(.horizontal)
                                    .padding(.top)

                                if !state.items.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        // Chart legend for rounded rates
                                        if state.roundingHint && !state.roundedRateIndices.isEmpty {
                                            HStack(spacing: 16) {
                                                HStack(spacing: 4) {
                                                    RoundedRectangle(cornerRadius: 2)
                                                        .fill(Color.purple)
                                                        .frame(width: 20, height: 12)
                                                    Text("Original rates")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }

                                                HStack(spacing: 4) {
                                                    RoundedRectangle(cornerRadius: 2)
                                                        .fill(Color.orange)
                                                        .frame(width: 20, height: 12)
                                                    Text("Adjusted rates")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            .padding(.horizontal)
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.bottom)
                                }

                                // Basal profile list
                                VStack(alignment: .leading, spacing: 0) {
                                    TherapySettingEditorView(
                                        items: $state.therapyItems,
                                        unit: .unitPerHour,
                                        timeOptions: state.timeValues,
                                        valueOptions: state.rateValues,
                                        roundedIndices: state.roundedRateIndices,
                                        originalRates: state.originalRates,
                                        validateOnDelete: state.validate,
                                        onItemAdded: {
                                            withAnimation {
                                                proxy.scrollTo(bottomID, anchor: .bottom)
                                            }
                                        }
                                    )
                                }
                                .padding(.horizontal)

                                if !state.items.isEmpty {
                                    totalBasalRow
                                }

                                HStack {
                                    Image(systemName: "hand.draw.fill")
                                        .padding(.leading)

                                    Text("Swipe to delete a single entry. Tap on it, to edit its time or value.")
                                        .padding(.trailing)
                                }
                                .font(.subheadline)
                                .fontWeight(.light)
                                .foregroundStyle(.secondary)
                                .padding()
                            }
                        }
                    }

                    saveButton
                }
                .background(appState.trioBackgroundColor(for: colorScheme))
                .alert(isPresented: $state.showAlert) {
                    Alert(
                        title: Text("Unable to Save"),
                        message: Text("Trio could not communicate with your pump. Changes to your basal profile were not saved."),
                        dismissButton: .default(Text("Close"))
                    )
                }
                .navigationTitle("Basal Rates")
                .navigationBarTitleDisplayMode(.automatic)
                .onAppear {
                    configureView()
                    state.validate()
                    state.therapyItems = state.getTherapyItems()
                }
                .onChange(of: state.therapyItems) { _, newItems in
                    state.updateFromTherapyItems(newItems)
                    state.calcTotal()
                    refreshUI = UUID()
                }
                .sheet(isPresented: $shouldDisplayHint) {
                    SettingInputHintView(
                        hintDetent: $hintDetent,
                        shouldDisplayHint: $shouldDisplayHint,
                        hintLabel: "Concentration & Basal Increment",
                        hintText: AnyView(
                            VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "Standard insulin concentration is U100 (100 units per mL), which is the baseline for most insulin pump delivery systems. To show this increment independent of units delivered, it can be shown as volume in μL/hr. The Pump Increment in μL/hr =  10 * Pump Increment in standard units/hr "
                                )
                                .font(.system(size: 16))

                                BulletList(
                                    listItems: [
                                        "U100 Concentration (Standard): Pumps typically have standard insulin delivery increments based on this concentration.",
                                        "Diluted Insulin: Lower concentration allows for finer insulin increments (more granular delivery options).",
                                        "Higher Concentration: Each pump increment delivers more insulin units, reducing granularity.",
                                        "Basal increment varies based on the insulin concentration in your cartridge."
                                    ],
                                    listItemSpacing: 10
                                )

                                Text("Example:")
                                    .font(.subheadline)
                                    .padding(.top, 5)

                                Text(
                                    "• In U100 insulin: 0.1 U increment delivers 0.1 units\n• In U50 insulin: 0.1 U increment delivers 0.05 units\n• In U200 insulin: 0.1 U increment delivers 0.2 units"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        ),
                        sheetTitle: "Insulin Concentration"
                    )
                }
            }
        }
    }
}
