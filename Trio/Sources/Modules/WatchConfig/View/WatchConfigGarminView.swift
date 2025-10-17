import SwiftUI

struct WatchConfigGarminView: View {
    @ObservedObject var state: WatchConfig.StateModel
    @State private var showDeviceList = false
    @State private var shouldDisplayHint: Bool = false
    @State var hintDetent = PresentationDetent.large

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    /// Handles deletion of devices from the device list
    private func onDelete(offsets: IndexSet) {
        state.devices.remove(atOffsets: offsets)
        state.deleteGarminDevice()
    }

    var body: some View {
        Group {
            if state.devices.isEmpty || showDeviceList {
                // No devices connected OR user wants to see device list - show device list/add view
                deviceListView
            } else {
                // Devices connected - go directly to configuration
                WatchConfigGarminAppConfigView(state: state)
                    .navigationTitle("Garmin App Settings")
                    .navigationBarTitleDisplayMode(.automatic)
                    .navigationBarBackButtonHidden(true)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: {
                                showDeviceList = true
                            }) {
                                HStack {
                                    Image(systemName: "chevron.left")
                                    Text("Garmin Devices")
                                }
                            }
                        }
                    }
            }
        }
        .id(state.devices.count) // Force view refresh when device count changes
        .onChange(of: state.devices.count) { _, newValue in
            // If devices were deleted and now empty, ensure we show device list
            if newValue == 0 {
                showDeviceList = false
            }
        }
    }

    var deviceListView: some View {
        Form {
            // MARK: - Device Configuration Section

            Section(
                header: Text("Garmin Configuration"),
                content: {
                    VStack {
                        Button {
                            state.selectGarminDevices()
                        } label: {
                            Text("Add Device")
                                .font(.title3)
                        }
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
                                    shouldDisplayHint.toggle()
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

            // MARK: - Device List Section

            if !state.devices.isEmpty {
                Section(
                    header: Text("Connected Watches"),
                    content: {
                        List {
                            ForEach(state.devices, id: \.uuid) { device in
                                Text(device.friendlyName)
                            }
                            .onDelete(perform: onDelete)
                        }
                    }
                ).listRowBackground(Color.chart)

                // MARK: - App Settings Navigation Section

                Section(
                    header: Text("Watch App Settings"),
                    content: {
                        Button(action: {
                            showDeviceList = false
                        }) {
                            HStack {
                                Text("Configure Watch Apps")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                ).listRowBackground(Color.chart)
            }
        }
        .listSectionSpacing(sectionSpacing)
        .navigationTitle("Garmin Devices")
        .navigationBarTitleDisplayMode(.automatic)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .sheet(isPresented: $shouldDisplayHint) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint,
                hintLabel: "Add Device",
                hintText: Text(
                    "Add Garmin Device to Trio. This happens via Garmin Connect. If you have multiple phones with Garmin Connect and the same Garmin device, you will run into connectivity issue between watch and phone depending of proximity of the phones, which might also affect your watchface function."
                ),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
    }
}
