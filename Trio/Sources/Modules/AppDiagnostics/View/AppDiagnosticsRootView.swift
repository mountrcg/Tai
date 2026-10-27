import SwiftUI
import Swinject

extension AppDiagnostics {
    struct RootView: BaseView {
        let resolver: Resolver

        @State var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @Environment(\.openURL) var openURL

        var body: some View {
            List {
                Section(
                    header: Text("Anonymized Data Sharing"),
                    content: {
                        VStack(alignment: .leading) {
                            ForEach(DiagnosticsSharingOption.allCases, id: \.self) { option in
                                Button(action: {
                                    state.diagnosticsSharingOption = option
                                }) {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(
                                            systemName: state
                                                .diagnosticsSharingOption == option ? "largecircle.fill.circle" : "circle"
                                        )
                                        .foregroundColor(state.diagnosticsSharingOption == option ? .accentColor : .secondary)
                                        .imageScale(.large)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(option.displayName)
                                                .foregroundColor(.primary)
                                                .bold()
                                            Text(option.caption)
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()
                                    }
                                    .background(Color.chart.opacity(0.65))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text(option.displayName))
                                .accessibilityValue(Text(option.caption))
                                .accessibilityAddTraits(
                                    state.diagnosticsSharingOption == option ? [.isButton, .isSelected] : .isButton
                                )
                            }
                            .padding()
                        }
                        .onChange(of: state.diagnosticsSharingOption) {
                            state.applyDiagnostics()
                        }
                    }
                ).listRowBackground(Color.chart)

                Section {
                    NavigationLink("What's sent") { TelemetryPreviewView() }
                    NavigationLink("Privacy details") { TelemetryPrivacyView() }
                }.listRowBackground(Color.chart)

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Why does Tai collect this data?").bold()
                        VStack(alignment: .leading, spacing: 4) {
                            BulletPoint(
                                String(
                                    localized: "App diagnostic insights — based on crash reports only — help us enhance app stability, ensure safety for all users, and quickly identify and resolve critical issues."
                                )
                            )
                            BulletPoint(
                                String(
                                    localized: "Tai collects the app's state on crash, device, iOS and general system info, and a stack trace."
                                )
                            )
                            BulletPoint(
                                String(
                                    localized: "Tai does not collect any health related data, e.g. glucose readings, insulin rates or doses, meal data, setting values, or similar."
                                )
                            )
                            BulletPoint(
                                String(
                                    localized: "Tai does not track any usage metrics or any other personal data about users other than the used iPhone model and iOS version."
                                )
                            )
                        }
                        Text(
                            "Diagnostics are sent to a Google Firebase Crashlytics project, which is securely maintained and accessed only by the Tai author."
                        )
//                        Spacer()
//                        Button {
//                            let numbers = [0]
//                            _ = numbers[1] // This will crash with index out of range
//                        } label: {
//                            Text("Test crashing Tai!")
//                                .foregroundColor(Color.orange)
//                                .frame(maxWidth: .infinity, alignment: .center)
//                        }
//                        .buttonStyle(.bordered)
                    }
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(Color.secondary)
                }.listRowBackground(Color.clear)
            }
            .listSectionSpacing(sectionSpacing)
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationBarTitle("App Diagnostics")
            .navigationBarTitleDisplayMode(.automatic)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Privacy Policy") {
                        if let url = URL(string: "https://github.com/nightscout/Trio/blob/dev/PRIVACY_POLICY.md") {
                            openURL(url)
                        } else {
                            fault(.ui, "Privacy policy URL is invalid")
                        }
                    }
                }
            }
        }
    }
}
