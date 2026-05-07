import SwiftUI

struct DetailPopupView: View {
    @Environment(\.colorScheme) var colorScheme
    let entry: autoISFHistory
    @Binding var isPopupPresented: Bool
    var units: GlucoseUnits
    var maxIOB: Decimal
    var iobThresholdPercent: Decimal
    var entries: [autoISFHistory] // Receive all entries
    @Binding var selectedEntry: autoISFHistory? // Selected entry
    var moveToPreviousEntry: () -> Void // Function for UP
    var moveToNextEntry: () -> Void // Function for DOWN

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                // Up Button
                Button(action: moveToPreviousEntry) {
                    Image(systemName: "chevron.up")
                        .font(.headline)
                        .foregroundColor(canMoveUp ? .primary : .secondary)
                }
                .disabled(!canMoveUp)

                Spacer()

                // Popup Heading
                Text("Calculation Details for \(formattedTime)")
                    .fontWeight(.semibold)

                Spacer()

                // Down Button
                Button(action: moveToNextEntry) {
                    Image(systemName: "chevron.down")
                        .font(.headline)
                        .foregroundColor(canMoveDown ? .primary : .secondary)
                }
                .disabled(!canMoveDown)
            }
            .padding(.horizontal, 15)
            .padding(.bottom, 5)

            VStack(alignment: .leading) {
                Text("acce-ISF: \(formattedWithTwoDecimals(entry.acce_ratio))")
                    .foregroundColor(.loopYellow)

                VStack(spacing: 6) {
                    HStack {
                        Text("BG Acceleration:")
                        Spacer()
                        Text(formattedWithTwoDecimals(entry.bg_acce))
                            .fontWeight(.light)
                    }
                    HStack {
                        Text("Correlation:")
                        Spacer()
                        Text(formattedCorrelation(entry.parabola_fit_correlation))
                            .fontWeight(.light)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }

            Divider()

            // Keep grid centered, align all contents to right
            HStack {
                Spacer() // Push the grid to center
                Grid(alignment: .trailing, horizontalSpacing: 30, verticalSpacing: 8) {
                    GridRow {
                        Text("Minutes").underline()
                        Text("Last Delta").underline()
                        Text("Next Delta").underline()
                    }
                    GridRow {
                        Text(formattedWithTwoDecimals(entry.parabola_fit_minutes)).fontWeight(.light)
                        Text(formattedGlucose(entry.parabola_fit_last_delta)).fontWeight(.light)
                        Text(formattedGlucose(entry.parabola_fit_next_delta)).fontWeight(.light)
                    }
                    GridRow {
                        Text("fit a0").underline()
                        Text("fit a1").underline()
                        Text("fit a2").underline()
                    }
                    GridRow {
                        Text(formattedWithTwoDecimals(entry.parabola_fit_a0)).fontWeight(.light)
                        Text(formattedWithTwoDecimals(entry.parabola_fit_a1)).fontWeight(.light)
                        Text(formattedWithTwoDecimals(entry.parabola_fit_a2)).fontWeight(.light)
                    }
                }
                Spacer() // Push grid to center
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Divider()

            VStack(alignment: .leading) {
                Text("dura_ISF: \(formattedWithTwoDecimals(entry.dura_ratio))")
                    .foregroundColor(.loopYellow)

                VStack(spacing: 6) {
                    HStack {
                        Text("BG Plateau:")
                        Spacer()
                        Text(formattedGlucose(entry.dura_avg)).fontWeight(.light)
                    }
                    HStack {
                        Text("Duration of Plateau:")
                        Spacer()
                        Text(formatted(entry.dura_min, unit: "min"))
                            .fontWeight(.light)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }

            Divider()

            VStack(alignment: .leading) {
                if let iob = entry.iob, let effIobTH = entry.iob_TH {
                    Text("IOB: \(formattedWithTwoDecimals(iob)) U")
                        .foregroundColor(.insulin)
                    VStack(alignment: .leading, spacing: 6) {
                        if maxIOB == effIobTH && iobThresholdPercent == 1 {
                            HStack {
                                Spacer()
                                Grid(alignment: .trailing, horizontalSpacing: 30, verticalSpacing: 8) {
                                    GridRow {
                                        Text("maxIOB").underline()
                                        Text("IOB / maxIOB").underline()
                                    }
                                    GridRow {
                                        Text(formatted(maxIOB, unit: "U")).fontWeight(.light)
                                        Text(formatted(100 * iob / maxIOB, unit: "%"))
                                            .fontWeight(.light)
                                            .foregroundColor(iob / maxIOB < 1 ? .loopGreen : .loopRed)
                                    }
                                }
                                Spacer()
                            }
                        } else {
                            HStack {
                                Spacer()
                                Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 8) {
                                    GridRow {
                                        Text("maxIOB").underline()
                                        Text("iobTH %").underline()
                                        if formatted(iobThresholdPercent) != formatted(effIobTH / maxIOB) {
                                            Text("adj.").underline()
                                        }
                                        Text("eff.TH").underline()
                                        Text("IOB / TH").underline()
                                    }
                                    GridRow {
                                        Text(formatted(maxIOB, unit: "U")).fontWeight(.light)
                                        Text(formatted(100 * iobThresholdPercent, unit: "%")).fontWeight(.light)
                                        if formatted(iobThresholdPercent) != formatted(effIobTH / maxIOB) {
                                            Text(formatted(100 * effIobTH / maxIOB, unit: "%")).fontWeight(.light)
                                        }
                                        Text(formatted(effIobTH, unit: "U")).fontWeight(.light)
                                        Text(formatted(100 * iob / effIobTH, unit: "%"))
                                            .fontWeight(.light)
                                            .foregroundColor(iob / effIobTH < 1 ? .loopGreen : .loopRed)
                                    }
                                }
                                Spacer()
                            }.font(.system(size: 12, design: .rounded))
                        }
                        Text("maxIOB and iobTH% as of current settings!")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    Divider()
                }
            }

            Button {
                isPopupPresented = false
            } label: {
                Text("Got it!")
                    .foregroundColor(Color.tabBar)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.bordered)
            .padding(.top, 6)
        }
        .font(.system(size: 14, design: .rounded))
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color("Chart"))
        )
        .frame(maxWidth: 325)
    }

    private var formattedTime: String {
        if let timestamp = entry.timestamp {
            return Formatter.timeFormatter.string(from: timestamp)
        }
        return "N/A"
    }

    private func formattedGlucose(_ value: Decimal?) -> String {
        guard let glucose = value else { return "N/A" }

        let converted = glucose.asUnit(units)
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.minimumFractionDigits = units == .mgdL ? 1 : 2
        formatter.maximumFractionDigits = units == .mgdL ? 1 : 2

        return "\(formatter.string(from: converted as NSDecimalNumber) ?? "\(converted)") \(units.rawValue)"
    }

    private func formattedCorrelation(_ value: Decimal?) -> String {
        guard let value = value else { return "N/A" }
        let percentageValue = value * 100
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "\(formatter.string(from: percentageValue as NSDecimalNumber) ?? "\(percentageValue)")%"
    }

    private func formattedWithTwoDecimals(_ value: Decimal?) -> String {
        guard let value = value else { return "N/A" }
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    private var currentIndex: Int? {
        entries.firstIndex(where: { $0 == selectedEntry })
    }

    private func formatted(_ value: Decimal?, unit: String = "") -> String {
        guard let value = value else { return "N/A" }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        let formattedValue = formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
        return unit.isEmpty ? formattedValue : "\(formattedValue) \(unit)"
    }

    private var canMoveUp: Bool {
        if let index = currentIndex {
            return index > 0
        }
        return false
    }

    private var canMoveDown: Bool {
        if let index = currentIndex {
            return index < entries.count - 1
        }
        return false
    }
}
