import Charts
import SwiftUI
import Swinject

extension CarbRatioEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var refreshUI = UUID()
        @State private var now = Date()
        @Namespace private var bottomID

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var saveButton: some View {
            ZStack {
                let shouldDisableButton = state.shouldDisplaySaving || state.items.isEmpty || !state.hasChanges

                Rectangle()
                    .frame(height: 65)
                    .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                    .background(.thinMaterial)
                    .opacity(0.8)
                    .clipShape(Rectangle())
                    .ignoresSafeArea(edges: .horizontal)

                Group {
                    HStack {
                        HStack {
                            Button {
                                let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                                impactHeavy.impactOccurred()
                                state.save()

                                // deactivate saving display after 1.25 seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                                    state.shouldDisplaySaving = false
                                }
                            } label: {
                                HStack {
                                    if state.shouldDisplaySaving {
                                        ProgressView().padding(.trailing, 10)
                                    }
                                    Text(state.shouldDisplaySaving ? "Saving..." : "Save")
                                }
                                .containerRelativeFrame(.horizontal) { width, _ in width * 0.9 }
                                .padding(10)
                            }
                        }
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.9 }
                        .disabled(shouldDisableButton)
                        .background(shouldDisableButton ? Color(.systemGray4) : Color(.systemBlue))
                        .tint(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(5)
            }
        }

        var body: some View {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack {
                            VStack(alignment: .leading, spacing: 0) {
                                // Calculate from CSF button
                                calculateFromCSFButton
                                    .padding(.horizontal)
                                    .padding(.top)

                                // Chart visualization
                                if !state.items.isEmpty {
                                    carbRatioChart
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
                                }

                                // Carb ratio list
                                TherapySettingEditorView(
                                    items: $state.therapyItems,
                                    unit: .gramPerUnit,
                                    timeOptions: state.timeValues,
                                    valueOptions: state.rateValues,
                                    validateOnDelete: state.validate,
                                    onItemAdded: {
                                        withAnimation {
                                            proxy.scrollTo(bottomID, anchor: .bottom)
                                        }
                                    }
                                )
                                .padding(.horizontal)

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
                .onAppear(perform: configureView)
                .navigationTitle("Carb Ratios")
                .navigationBarTitleDisplayMode(.automatic)
                .onAppear {
                    state.validate()
                    state.therapyItems = state.getTherapyItems()
                }
                .onChange(of: state.therapyItems) { _, newItems in
                    state.updateFromTherapyItems(newItems)
                    refreshUI = UUID()
                }
            }
        }

        // Calculate from CSF Button
        @State private var shouldDisplayCSFHint: Bool = false

        private var calculateFromCSFButton: some View {
            HStack {
                Button {
                    let impactMedium = UIImpactFeedbackGenerator(style: .medium)
                    impactMedium.impactOccurred()
                    state.calculateCRFromCSF()
                } label: {
                    Text("Calculate CR from CSF & ISF Profiles")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    shouldDisplayCSFHint.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .sheet(isPresented: $shouldDisplayCSFHint) {
                SettingInputHintView(
                    hintDetent: .constant(.large),
                    shouldDisplayHint: $shouldDisplayCSFHint,
                    hintLabel: String(localized: "Calculate CR from CSF & ISF Profiles"),
                    hintText: AnyView(
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "This button re-calculates your Carb Ratio (CR) profile from your Insulin Sensitivity Factor (ISF) and Carb Sensitivity Factor (CSF) profiles using the formula: CR = ISF / CSF."
                            )
                            Text(
                                "Carb Sensitivity Factor (CSF) represents how much your blood glucose rises per gram of carbohydrate consumed. It describes the digestive process of carbs entering your bloodstream as glucose — a process that is independent of insulin sensitivity."
                            )
                            Text(
                                "Because CR combines two independent physiological processes — CSF (carb absorption into blood) and ISF (insulin moving glucose out of blood) — calculating CR this way ensures it adjusts correctly across the day as your ISF profile changes, while CSF remains stable. If you do experience variation in carb absorption throughout the day, you can account for that in your CSF profile based on real physiological differences, rather than having CSF implicitly change as a mathematical side effect of a fixed CR and varying ISF."
                            )
                            Text(
                                "If the \"Use Profile CSF\" setting is enabled in Algorithm Additionals, the algorithm will also keep CSF independent of dynamic ISF adjustments from autoISF, Autosens, or Dynamic ISF. This effectively makes your CR dynamic at runtime too — some refer to this as \"dynamic CR\"."
                            )
                            Text(
                                "Tip: Start with a single CSF value for the entire day. Look at your current ISF and CR values at a time of day where you feel most confident they are working well — usually around midday — and calculate CSF = ISF / CR from those values."
                            )
                        }
                    ),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
        }

        // Chart for visualizing carb ratios
        private var carbRatioChart: some View {
            Chart {
                ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                    let displayValue = state.rateValues[item.rateIndex]

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
                            colors: [
                                Color.orange.opacity(0.6),
                                Color.orange.opacity(0.1)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    ).alignsMarkStylesWithPlotArea()

                    LineMark(x: .value("End Date", startDate), y: .value("Ratio", displayValue))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.orange)

                    LineMark(x: .value("Start Date", endDate), y: .value("Ratio", displayValue))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.orange)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Carb ratio profile chart, 24 hours"))
        }
    }
}

extension NumberFormatter {
    static var csfFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }
}
