import SwiftUI

struct ChartLegendView: View {
    @Environment(AppState.self) var appState
    @Environment(\.colorScheme) var colorScheme

    var state: Home.StateModel

    @State var legendSheetDetent = PresentationDetent.large

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                Text(
                    "The main chart in Trio is made up of various elements and shapes. Find their meanings below."
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 50)

                List {
                    Section {
                        VStack(alignment: .leading) {
                            Text("Chart Gestures").bold().padding(.bottom, 5).textCase(.uppercase)

                            DefinitionRow(
                                term: String(localized: "Drag"),
                                definition: Text(
                                    "Drag the chart sideways to pan through your history. Flick and let go to keep it gliding; panning far enough back loads up to 72 hours."
                                ),
                                color: Color.primary,
                                iconString: "hand.draw"
                            )

                            DefinitionRow(
                                term: String(localized: "Pinch"),
                                definition: Text(
                                    "Pinch to zoom the visible time window continuously, between 1 and 24 hours."
                                ),
                                color: Color.primary,
                                iconString: "arrow.down.left.and.arrow.up.right"
                            )

                            DefinitionRow(
                                term: String(localized: "Double Tap"),
                                definition: Text("Cycles the zoom through the 6, 12 and 24 hour presets."),
                                color: Color.primary,
                                iconString: "hand.tap"
                            )

                            DefinitionRow(
                                term: String(localized: "Triple Tap"),
                                definition: Text(
                                    "Recenters the chart on now, from wherever you have panned to. The zoom level stays as it is."
                                ),
                                color: Color.primary,
                                iconString: "hand.tap.fill"
                            )

                            DefinitionRow(
                                term: String(localized: "Touch and Hold"),
                                definition: VStack(alignment: .leading, spacing: 10) {
                                    Text(
                                        "Rest your finger on the chart to inspect a single reading with its IOB and COB."
                                    )
                                    Text(
                                        "Keep your finger down and slide to scrub along the curve; slide to either edge and the chart pans along with you."
                                    )
                                },
                                color: Color.primary,
                                iconString: "hand.point.up.left"
                            )
                        }.listRowBackground(Color.gray.opacity(0.1))
                    }

                    Section {
                        VStack(alignment: .leading) {
                            Text("Home Screen Gestures").bold().padding(.bottom, 5).textCase(.uppercase)

                            VStack(alignment: .leading) {
                                HStack {
                                    if #available(iOS 18.0, *) {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .symbolEffect(
                                                .rotate.counterClockwise.byLayer,
                                                options: .repeat(.periodic(delay: 5.0))
                                            )
                                            .foregroundStyle(Color.primary)
                                    } else {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .foregroundStyle(Color.primary)
                                    }
                                    Text("Pull Down").font(.subheadline).fontWeight(.semibold)
                                }.padding(.bottom, 5)
                                Text("Pull the home screen down past the hint to force a loop.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 5)

                            DefinitionRow(
                                term: String(localized: "Tap Tai Button"),
                                definition: Text("Opens the treatment view to add carbs, insulin or a manual glucose reading."),
                                color: Color.primary,
                                iconString: "hand.tap"
                            )

                            if state.enableQuickPickTreatments {
                                DefinitionRow(
                                    term: String(localized: "Hold Trio Button"),
                                    definition: Text(
                                        "Opens the Quick-Pick Treatments picker with your recent bolus and carb amounts, so a repeat treatment takes one slide to confirm."
                                    ),
                                    color: Color.primary,
                                    iconString: "hand.point.up.left"
                                )
                            }

                            DefinitionRow(
                                term: String(localized: "Tap Loop Pill"),
                                definition: Text("Shows the status popup with the details of the last loop cycle."),
                                color: Color.primary,
                                iconString: "hand.tap"
                            )

                            DefinitionRow(
                                term: String(localized: "Swipe Up on Status Popup"),
                                definition: Text("Dismisses the loop status popup again."),
                                color: Color.primary,
                                iconString: "hand.draw"
                            )

                            DefinitionRow(
                                term: String(localized: "Tap Glucose or Pump Panel"),
                                definition: Text(
                                    "Opens the setup for that device — or, if none is set up yet, the picker to add one."
                                ),
                                color: Color.primary,
                                iconString: "hand.tap"
                            )
                        }.listRowBackground(Color.gray.opacity(0.1))
                    }

                    Section {
                        VStack(alignment: .leading) {
                            Text("Forecasts").bold().padding(.bottom, 5).textCase(.uppercase)
                            Text(
                                "The oref algorithm determines insulin dosing based on a number of scenarios that it estimates with different types of forecasts."
                            )
                            .font(.subheadline)
                            .foregroundColor(.primary)

                            if state.forecastDisplayType == .lines {
                                legendLinesView
                            } else {
                                legendConeOfUncertaintyView
                            }
                        }.listRowBackground(Color.gray.opacity(0.1))

                        VStack(alignment: .leading) {
                            Text("Other Elements & Shapes").bold().padding(.bottom, 5).textCase(.uppercase)

                            DefinitionRow(
                                term: String(localized: "IOB value"),
                                definition: Text(
                                    "Shows current IOB in insulin units."
                                ),
                                color: Color.insulin,
                                iconString: "drop.circle"
                            )

                            VStack(alignment: .leading) {
                                HStack {
                                    Image("premeal")
                                        .renderingMode(.template)
                                        .resizable()
                                        .frame(width: 15, height: 15)
                                        .foregroundColor(.loopYellow)
                                    Text("COB value").font(.subheadline).fontWeight(.semibold)
                                }.padding(.bottom, 5)
                                Text(
                                    "Shows current COB amount in g."
                                )
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 5)

                            VStack(alignment: .leading) {
                                HStack {
                                    Image(systemName: "chart.bar.xaxis")
                                        .rotationEffect(Angle(degrees: 180))
                                        .foregroundStyle(LinearGradient(
                                            colors: [.insulinTintColor.opacity(1), .insulinTintColor.opacity(0.4)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ))
                                    Text("Basal rate").font(.subheadline).fontWeight(.semibold)
                                }.padding(.bottom, 5)
                                Text(
                                    "Shows current basal rate being delivered in insulin units per hour."
                                )
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 5)

                            DefinitionRow(
                                term: String(localized: "Reservoir"),
                                definition: Text(
                                    "Shows decreasing Pump Reservoir levels, progressively colorized from green to red."
                                ),
                                color: Color.insulin,
                                iconString: "gauge.with.dots.needle.67percent"
                            )

                            DefinitionRow(
                                term: String(localized: "ISF value"),
                                definition: Text(
                                    "Currently used Insulin Sensitivity Factor (ISF) in mg/dL or mmol/L per IU."
                                ),
                                color: Color.loopGreen,
                                iconString: "arrow.up.arrow.down"
                            )

                            VStack(alignment: .leading) {
                                HStack {
                                    Text("⇢")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.secondary)
                                    Text("Eventual BG value").font(.subheadline).fontWeight(.semibold)
                                }.padding(.bottom, 5)
                                Text(
                                    "If all insulin delivery stopped, and assuming no food is eaten or other significant changes occur, at what level would blood glucose eventually level off within 3-4 hrs."
                                )
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 5)

                            DefinitionRow(
                                term: String(localized: "TDD 24h"),
                                definition: Text(
                                    "Shows the total dose of insulin for the last 24 hours."
                                ),
                                color: Color.insulin,
                                iconString: "ivfluid.bag"
                            )

                            DefinitionRow(
                                term: String(localized: "autoISF Sens Ratio (aiSR)"),
                                definition: Text(
                                    "Shows current final ISF / Sensitivity adjustment Ratio as derived by autoISF algorithm."
                                ),
                                color: Color.loopGreen,
                                iconString: "arrow.up.arrow.down"
                            )

                            DefinitionRow(
                                term: String(localized: "autosens Ratio (AS)"),
                                definition: Text(
                                    "Shows current final ISF / Sensitivity adjustment Ratio as derived by autosens algorithm. Only shown when autoISF is not enabled."
                                ),
                                color: Color.zt,
                                iconString: "arrow.up.arrow.down"
                            )

                            DefinitionRow(
                                term: String(localized: "Scheduled Basal Rate"),
                                definition: VStack(alignment: .leading, spacing: 10) {
                                    Text("This dotted line represents the hourly insulin rate of your scheduled basal insulin.")
                                    Text(
                                        "To review or change your scheduled basal rates, go to Settings > Therapy > Basal Rates."
                                    )
                                },
                                color: Color.insulin,
                                iconString: "ellipsis"
                            )

                            DefinitionRow(
                                term: String(localized: "Temporary Basal Rate (TBR)"),
                                definition: Text(
                                    "Shows current or past TBRs, which can be set by the oref algorithm or manually."
                                ),
                                color: Color.insulin,
                                iconString: "square"
                            )

                            DefinitionRow(
                                term: String(localized: "Pump Suspension"),
                                definition: Text("Indicates when insulin delivery was paused, i.e. pump is suspended."),
                                color: Color.loopGray.opacity(colorScheme == .dark ? 0.3 : 0.8),
                                iconString: "square.fill"
                            )

                            DefinitionRow(
                                term: String(localized: "CGM Glucose Value"),
                                definition: VStack(alignment: .leading, spacing: 10) {
                                    if state.settingsManager.settings.smoothGlucose {
                                        Text(
                                            "Displays real-time glucose readings from your CGM that were smoothed using the Savitzky-Golay filter. The displayed glucose readings may not match the actual readings from your CGM."
                                        )
                                        Text(
                                            "Depending on your user interface settings, this may be displayed in a static (red, green, orange) or dynamic (full color spectrum) coloring scheme."
                                        )
                                    } else {
                                        Text(
                                            "Displays real-time glucose readings from your CGM. Depending on your user interface settings, this may be displayed in a static (red, green, orange) or dynamic (full color spectrum) coloring scheme."
                                        )
                                    }
                                    Text(
                                        "To modify how glucose readings are displayed, go to Settings > Features > User Interface > Glucose Color Scheme."
                                    )
                                    if state.settingsManager.settings.smoothGlucose {
                                        Text(
                                            "To disable smoothing, go to Settings > Devices > Continuous Glucose Monitor > Smooth Glucose Value and toggle off the setting."
                                        )
                                    }
                                },
                                color: Color.green,
                                iconString: state.settingsManager.settings.smoothGlucose ? "record.circle.fill" : "circle.fill"
                            )

                            DefinitionRow(
                                term: String(localized: "Manual Glucose Measurement"),
                                definition: Text("Manually entered blood glucose, such as a fingerstick test."),
                                color: Color.red,
                                iconString: "drop.fill"
                            )

                            DefinitionRow(
                                term: String(localized: "SMB"),
                                definition: Text(
                                    "Shows a small automated insulin dose (super-micro-bolus)."
                                ),
                                color: Color.insulin,
                                iconString: "arrowtriangle.down.fill"
                            )

                            DefinitionRow(
                                term: String(localized: "Manual Bolus"),
                                definition: Text(
                                    "Shows a manually entered insulin dose."
                                ),
                                color: Color.teal,
                                iconString: "circle.fill"
                            )

                            DefinitionRow(
                                term: String(localized: "External Bolus"),
                                definition: Text(
                                    "Shows an externally administered insulin dose (e.g., a pen shot)."
                                ),
                                color: Color.purple,
                                iconString: "rhombus.fill"
                            )

                            DefinitionRow(
                                term: String(localized: "Carb Entry"),
                                definition: Text("Tracks the carbohydrates you eat, entered to guide insulin dosing."),
                                color: Color.loopYellow,
                                iconString: "circle.fill"
                            )

                            DefinitionRow(
                                term: String(localized: "Fat-Protein Carb Equivalent"),
                                definition: VStack(alignment: .leading, spacing: 10) {
                                    Text(
                                        "Represents carb equivalent for fat and protein, calculated using the Warsaw Method."
                                    )
                                    Text(
                                        "To enable or configure Warsaw Method application in Trio, go to Settings > Features > Meal Settings."
                                    )
                                },
                                color: Color.brown,
                                iconString: "circle.fill"
                            )

                            DefinitionRow(
                                term: String(localized: "Override"),
                                definition: Text(
                                    "Indicates when an override is or was active, temporarily changing therapy settings (e.g., basal rate, insulin sensitivity, carb ratio, target glucose, or whether Trio can dose SMBs)."
                                ),
                                color: Color.purple.opacity(0.4),
                                iconString: "button.horizontal.fill"
                            )

                            DefinitionRow(
                                term: String(localized: "Temporary Target"),
                                definition: Text(
                                    "Marks when a short-term temporary glucose target is or was active, (potentially) altering when or how much insulin is delivered."
                                ),
                                color: Color.green.opacity(0.4),
                                iconString: "button.horizontal.fill"
                            )

                            DefinitionRow(
                                term: String(localized: "Past Insulin-on-Board (IOB)"),
                                definition: Text(
                                    "Shows the IOB value calculated by the algorithm at a specific time in the past. These values are snapshots and won’t change if insulin is added or removed after the fact."
                                ),
                                color: Color.darkerBlue.opacity(0.8),
                                iconString: "line.diagonal"
                            )

                            DefinitionRow(
                                term: String(localized: "Past Carbs-on-Board (COB)"),
                                definition: Text(
                                    "Shows the COB value calculated by the algorithm at a specific time in the past. These values are snapshots and won’t change if carbs are added or removed after the fact."
                                ),
                                color: Color.orange.opacity(0.8),
                                iconString: "line.diagonal"
                            )
                        }.listRowBackground(Color.gray.opacity(0.1))
                    }
                }
                .scrollContentBackground(.hidden)
                .navigationBarTitle("Chart Legend", displayMode: .inline)
                .padding(.trailing, 10)
                .padding(.bottom, 15)

                Button {
                    state.isLegendPresented.toggle()
                } label: {
                    Text("Got it!").bold().frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
                }
                .buttonStyle(.bordered)
                .padding(.top)
            }
            .padding([.horizontal, .bottom])
            .listSectionSpacing(10)
            .ignoresSafeArea(edges: .top)
            .presentationDetents(
                [.fraction(0.9), .large],
                selection: $legendSheetDetent
            )
        }
    }

    var legendLinesView: some View {
        Group {
            DefinitionRow(
                term: String(localized: "IOB (Insulin on Board)"),
                definition: Text(
                    "Forecasts future glucose readings based on the amount of insulin still active in the body."
                ),
                color: .insulin
            )

            DefinitionRow(
                term: String(localized: "ZT (Zero-Temp)"),
                definition: Text(
                    "Forecasts the worst-case future glucose reading scenario if no carbs are absorbed and insulin delivery is stopped until glucose starts rising."
                ),
                color: .zt
            )

            DefinitionRow(
                term: String(localized: "COB (Carbs on Board)"),
                definition: Text(
                    "Forecasts future glucose reading changes by considering the amount of carbohydrates still being absorbed in the body."
                ),
                color: .loopYellow
            )

            DefinitionRow(
                term: String(localized: "UAM (Unannounced Meal)"),
                definition: Text(
                    "Forecasts future glucose levels and insulin dosing needs for unexpected meals or other causes of glucose reading increases without prior notice."
                ),
                color: .uam
            )
        }
    }

    var legendConeOfUncertaintyView: some View {
        DefinitionRow(
            term: String(localized: "Cone of Uncertainty"),
            definition: VStack(alignment: .leading, spacing: 10) {
                Text(
                    "For simplicity reasons, oref's various forecast curves are displayed as a \"Cone of Uncertainty\" that depicts a possible, forecasted range of future glucose fluctuation based on the current data and the algorithm's result."
                )
                Text(
                    "To modify how the forecast is displayed, go to Settings > Features > User Interface > Forecast Display Type."
                )
            },
            color: Color.blue.opacity(0.5)
        )
    }
}
