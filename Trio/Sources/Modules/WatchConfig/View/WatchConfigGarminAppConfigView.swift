import SwiftUI

struct WatchConfigGarminAppConfigView: View {
    @ObservedObject var state: WatchConfig.StateModel

    @State private var shouldDisplayHint1: Bool = false
    @State private var shouldDisplayHint2: Bool = false
    @State private var shouldDisplayHint3: Bool = false
    @State private var shouldDisplayHint4: Bool = false
    @State var hintDetent = PresentationDetent.large

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        Form {
            // MARK: - Watchface Selection Section

            Section(
                content: {
                    VStack {
                        Picker(
                            selection: $state.garminWatchface,
                            label: Text("Watch App selection").multilineTextAlignment(.leading)
                        ) {
                            ForEach(GarminWatchface.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }
                        .padding(.top)
                        .onChange(of: state.garminWatchface) { _ in
                            state.handleWatchfaceChange()
                        }

                        HStack(alignment: .center) {
                            Text(
                                "Choose which watchface/datafield to support."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    shouldDisplayHint1.toggle()
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)
                    }.padding(.vertical)
                }
            ).listRowBackground(Color.chart)

            // MARK: - Disable Watchface Data Section

            Section(
                content: {
                    VStack {
                        Toggle("Disable Watchface Data", isOn: $state.garminDisableWatchfaceData)
                            .disabled(state.isDisableToggleLocked)

                        // Display cooldown warning when toggle is locked
                        if state.isDisableToggleLocked {
                            HStack {
                                Text(
                                    "Please wait \(state.remainingCooldownSeconds) seconds!\n\n" +
                                        "After the lockout you can re-enable watchface data transmission, but you need to change to the new watchface on your Garmin watch before that - e.g. now!"
                                )
                                .font(.footnote)
                                .foregroundColor(.orange)
                                .multilineTextAlignment(.leading)
                                .lineLimit(nil)
                                Spacer()
                            }
                        }

                        HStack(alignment: .center) {
                            Text(
                                "Choose if you only want to use a datafield and no supported watchface!"
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    shouldDisplayHint2.toggle()
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)
                    }.padding(.vertical)
                }
            ).listRowBackground(Color.chart)

            // MARK: - Data Type 1 Selection Section

            Section(
                content: {
                    VStack {
                        Picker(
                            selection: $state.garminDataType1,
                            label: Text("Data Field 1").multilineTextAlignment(.leading)
                        ) {
                            ForEach(GarminDataType1.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }.padding(.top)
                        HStack(alignment: .center) {
                            Text(
                                "Choose between display of COB or Sensitivity Ratio on Garmin device."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    shouldDisplayHint3.toggle()
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)
                    }.padding(.vertical)
                }
            ).listRowBackground(Color.chart)

            // MARK: - Data Type 2 Selection Section (SwissAlpine Only)

            if state.garminWatchface == .swissalpine {
                Section(
                    content: {
                        VStack {
                            Picker(
                                selection: $state.garminDataType2,
                                label: Text("Data Field 2").multilineTextAlignment(.leading)
                            ) {
                                ForEach(GarminDataType2.allCases) { selection in
                                    Text(selection.displayName).tag(selection)
                                }
                            }.padding(.top)
                            HStack(alignment: .center) {
                                Text(
                                    "Choose between display of TBR or Eventual BG on Garmin device."
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                Spacer()
                                Button(
                                    action: {
                                        shouldDisplayHint4.toggle()
                                    },
                                    label: {
                                        HStack {
                                            Image(systemName: "questionmark.circle")
                                        }
                                    }
                                ).buttonStyle(BorderlessButtonStyle())
                            }.padding(.top)
                        }.padding(.vertical)
                    }
                ).listRowBackground(Color.chart)
            }
        }
        .listSectionSpacing(sectionSpacing)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))

        // MARK: - Help Sheets

        .sheet(isPresented: $shouldDisplayHint1) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint1,
                hintLabel: "Choose Garmin App support.",
                hintText: Text(
                    "Choose which watchface and datafield combination on your Garmin device you wish to provide data for. Trying to use watchfaces and data fields of different developers will not work. Both must use the same data structure provided by Trio.\n\n" +
                        "Also you have to use this configuration setting here BEFORE you switch the watchface on your Garmin device to another watchface.\n\n" +
                        "⚠️ Changing the watchface will automatically disable data transmission and lock that setting for 20 seconds to allow time for you to switch the watchface on your Garmin device."
                ),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
        .sheet(isPresented: $shouldDisplayHint2) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint2,
                hintLabel: "Disable watchface data transmission",
                hintText: Text(
                    "Important: If you want to use a different watchface on your Garmin device that has no data requirement from this app, use this toggle to disable all data transmission to the Garmin watchface app! Otherwise you will not be able to get current data once you re-enable the supported watchface that shows Trio data and you will have to re-install it on your Garmin device.\n\n" +
                        "Note: When switching between supported watchfaces, data transmission is automatically disabled for 20 seconds. You would manually need to re-enable it."
                ),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
        .sheet(isPresented: $shouldDisplayHint3) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint3,
                hintLabel: "Choose data support",
                hintText: Text(
                    "Choose which data type, along BG and IOB etc., you want to show on your Garmin device. That data type will be shown both on watchface and datafield"
                ),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
        .sheet(isPresented: $shouldDisplayHint4) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint4,
                hintLabel: "Choose data support",
                hintText: Text(
                    "Choose which data type, along BG and IOB etc., you want to show on your Garmin device. That data type will be shown both on watchface and datafield"
                ),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
    }
}
