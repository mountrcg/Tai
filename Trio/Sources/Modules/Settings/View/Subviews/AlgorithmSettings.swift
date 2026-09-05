//
//  FeatureSettingsView.swift
//  Trio
//
//  Created by Deniz Cengiz on 26.07.24.
//
import Foundation
import SwiftUI
import Swinject

struct AlgorithmSettings: BaseView {
    let resolver: Resolver

    @ObservedObject var state: Settings.StateModel

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        Form {
            Section(
                header: Text("Oref Algorithm"),
                content: {
                    Text("Autosens").navigationLink(to: .autosensSettings, from: self)
                    Text("Super Micro Bolus (SMB)").navigationLink(to: .smbSettings, from: self)
                    Text("Target Behavior").navigationLink(to: .targetBehavior, from: self)
                    Text("Additionals").navigationLink(to: .algorithmAdvancedSettings, from: self)
                }
            ).listRowBackground(Color.chart)
            Section(
                header: Text("Extensions"),
                content: {
                    Text("DynamicISF").navigationLink(to: .dynamicISF, from: self)
                    Text("autoISF").navigationLink(to: .autoISFSettings, from: self)
                    Text("AIMI B30").navigationLink(to: .b30Settings, from: self)
                    Text("Keto Protection").navigationLink(to: .ketoProtectSettings, from: self)
                }
            ).listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Algorithm Settings")
        .navigationBarTitleDisplayMode(.automatic)
    }
}
