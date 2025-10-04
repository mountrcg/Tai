import SwiftUI

struct WatchConfigGarminView: View {
    @ObservedObject var state: WatchConfig.StateModel

    @State private var shouldDisplayHint1: Bool = false
    @State private var shouldDisplayHint2: Bool = false
    @State var hintDetent = PresentationDetent.large
    @State var selectedVerboseHint: AnyView?
    @State var hintLabel: String?
    @State private var decimalPlaceholder: Decimal = 0.0
    @State private var booleanPlaceholder: Bool = false

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    private func onDelete(offsets: IndexSet) {
        state.devices.remove(atOffsets: offsets)
        state.deleteGarminDevice()
    }

    var body: some View {
        Form {
            Section(
                header: Text("Garmin Configuration"),
                content:
                {
                    VStack {
                        Button {
                            state.selectGarminDevices()
                        } label: {
                            Text("Add Device")
                                .font(.title3) }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .buttonStyle(.bordered)

                        HStack(alignment: .center) {
                            Text(
                                "Add a Garmin Device to Trio."
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

            Section(
                header: Text("Garmin Watch Settings"),
                content: {
                    VStack {
                        Picker(
                            selection: $state.garminWatchSetting,
                            label: Text("Data Choice").multilineTextAlignment(.leading)
                        ) {
                            ForEach(GarminWatchSetting.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }.padding(.top)
                        HStack(alignment: .center) {
                            Text(
                                "Choose which data to display on Garmin device."
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

            if !state.devices.isEmpty {
                Section(
                    header: Text("Garmin Watch"),
                    content: {
                        List {
                            ForEach(state.devices, id: \.uuid) { device in
                                Text(device.friendlyName)
                            }
                            .onDelete(perform: onDelete)
                        }
                    }
                ).listRowBackground(Color.chart)
            }
        }
        .listSectionSpacing(sectionSpacing)
        .sheet(isPresented: $shouldDisplayHint1) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint1,
                hintLabel: "Add Device",
                hintText: Text(
                    "Add Garmin Device to Trio. Please look at the docs to see which devices are supported."
                ),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
        .sheet(isPresented: $shouldDisplayHint2) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint2,
                hintLabel: "Choose data support",
                hintText: Text(
                    "Choose which data type, along BG and IOB etc., you want to show on your Garmin device. That data type will be shown both on watchface and datafield"
                ),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
        .navigationTitle("Garmin")
        .navigationBarTitleDisplayMode(.automatic)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
    }
}
