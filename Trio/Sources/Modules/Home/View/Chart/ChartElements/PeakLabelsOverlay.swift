import Charts
import Foundation
import SwiftUI

/// Renders BG peak labels with collision avoidance against bolus/carb bar marks and the
/// glucose curve. Bars stay anchored to the curve at a fixed pixel offset; labels move
/// to find a collision-free position via `LabelPlacement.placeLabelCenter`.
struct PeakLabelsOverlay: View {
    @Environment(\.colorScheme) private var colorScheme

    let proxy: ChartProxy
    let peaks: [(date: Date, glucose: Int16, type: ExtremumType)]
    let glucoseData: [GlucoseStored]
    let insulinData: [PumpEventStored]
    let carbData: [CarbEntryStored]
    let units: GlucoseUnits
    let highGlucose: Decimal
    let lowGlucose: Decimal
    let glucoseColorScheme: GlucoseColorScheme
    let currentGlucoseTarget: Decimal
    let screenHours: Int16

    private static let labelMargin: CGFloat = 4
    private static let labelDesiredOffset: CGFloat = 18
    private static let maxPlacementDistance: CGFloat = 80
    private static let glucoseDotSize: CGFloat = 6

    private static let barLabelHeight: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            if let plotAnchor = proxy.plotFrame {
                let plotRect = geo[plotAnchor]
                let obstacles = computeObstacles(plotRect: plotRect)
                let placed = computePlacements(obstacles: obstacles, plotRect: plotRect)

                ZStack(alignment: .topLeading) {
                    ForEach(placed.indices, id: \.self) { i in
                        let p = placed[i]
                        // Connector from peak point on the curve to the label edge.
                        Path { path in
                            path.move(to: CGPoint(x: p.peakX, y: p.peakY))
                            path.addLine(to: connectorAnchor(rect: p.rect, peakY: p.peakY))
                        }
                        .stroke(Color.secondary, lineWidth: 0.75)
                        .opacity(0.75)

                        PeakLabelBadge(text: p.text, color: p.color)
                            .fixedSize()
                            .position(x: p.rect.midX, y: p.rect.midY)
                    }
                }
                .frame(width: plotRect.width, height: plotRect.height)
                .offset(x: plotRect.minX, y: plotRect.minY)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Placement

    private struct PlacedPeak {
        let rect: CGRect
        let peakX: CGFloat
        let peakY: CGFloat
        let text: String
        let color: Color
    }

    /// Anchor on the label rect closest to the peak point — vertically above or below
    /// depending on which side of `peakY` the rect ended up on, clamped horizontally
    /// inside the rect to keep diagonal connectors short.
    private func connectorAnchor(rect: CGRect, peakY: CGFloat) -> CGPoint {
        let y = rect.midY <= peakY ? rect.maxY : rect.minY
        return CGPoint(x: rect.midX, y: y)
    }

    private func computePlacements(obstacles: [CGRect], plotRect _: CGRect) -> [PlacedPeak] {
        let sortedObstacles = obstacles.sorted { $0.minX < $1.minX }
        let labelSize = CGSize(width: 30, height: 18)

        return peaks.compactMap { peak -> PlacedPeak? in
            let glucoseDecimal = Decimal(peak.glucose)
            let displayValue = units == .mgdL ? glucoseDecimal : glucoseDecimal.asMmolL
            guard let cx = proxy.position(forX: peak.date),
                  let cy = proxy.position(forY: displayValue) else { return nil }

            // Plot-relative coordinates
            let cxRel = cx
            let cyRel = cy

            let desiredCenterY: CGFloat
            let side: VerticalSide
            switch peak.type {
            case .max:
                desiredCenterY = cyRel - Self.labelDesiredOffset
                side = .above
            case .min:
                desiredCenterY = cyRel + Self.labelDesiredOffset
                side = .below
            case .none:
                desiredCenterY = cyRel
                side = .both
            }

            let desiredRect = CGRect(
                x: cxRel - labelSize.width / 2,
                y: desiredCenterY - labelSize.height / 2,
                width: labelSize.width,
                height: labelSize.height
            )

            let placedRect = sortedObstacles.placeLabelCenter(
                desiredRect: desiredRect,
                verticalSide: side,
                maxDistance: Self.maxPlacementDistance
            ) ?? desiredRect

            return PlacedPeak(
                rect: placedRect,
                peakX: cxRel,
                peakY: cyRel,
                text: formattedGlucose(Int(peak.glucose)),
                color: peakColor(glucose: glucoseDecimal)
            )
        }
    }

    // MARK: - Obstacles

    private var maxBolusValue: Decimal {
        let amounts = insulinData.compactMap { $0.bolus?.amount?.decimalValue }
        return amounts.max() ?? 1
    }

    private var maxCarbsValue: Decimal {
        carbData.map { Decimal($0.carbs) }.max() ?? 1
    }

    private func computeObstacles(plotRect _: CGRect) -> [CGRect] {
        var rects: [CGRect] = []
        let maxBolus = maxBolusValue
        let maxCarbs = maxCarbsValue

        // Glucose curve dots
        for g in glucoseData {
            guard let date = g.date else { continue }
            let glucoseDecimal = Decimal(g.glucose)
            let displayValue = units == .mgdL ? glucoseDecimal : glucoseDecimal.asMmolL
            guard let x = proxy.position(forX: date),
                  let y = proxy.position(forY: displayValue) else { continue }
            rects.append(CGRect(
                x: x - Self.glucoseDotSize / 2,
                y: y - Self.glucoseDotSize / 2,
                width: Self.glucoseDotSize,
                height: Self.glucoseDotSize
            ))
        }

        // Bolus / SMB bars (extend up from curve)
        for insulin in insulinData {
            guard let bolus = insulin.bolus, bolus.isExternal == false else { continue }
            let amount = (bolus.amount ?? 0 as NSDecimalNumber).decimalValue
            guard amount != 0 else { continue }
            let date = insulin.timestamp ?? Date()
            guard let glucose = MainChartHelper.timeToNearestGlucose(
                glucoseValues: glucoseData,
                time: date.timeIntervalSince1970
            )?.glucose else { continue }

            let displayValue = units == .mgdL ? Decimal(glucose) : Decimal(glucose).asMmolL
            guard let x = proxy.position(forX: date),
                  let y = proxy.position(forY: displayValue) else { continue }

            let barWidth = MainChartHelper.bolusBarWidth(
                amount: amount,
                minimumSMB: MainChartHelper.Config.smbWidthThreshold,
                screenHours: screenHours
            )
            let barHeight = MainChartHelper.bolusBarHeight(amount: amount, maxAmount: maxBolus)
            let totalHeight = MainChartHelper.Config.bolusBarSpacing + barHeight + MainChartHelper.Config
                .bolusAnnotationSpacing + Self.barLabelHeight
            rects.append(CGRect(
                x: x - max(barWidth, 14) / 2, // widen a bit so rotated labels aren't tightly clipped
                y: y - totalHeight,
                width: max(barWidth, 14),
                height: totalHeight
            ))
        }

        // Carb bars (extend down from curve)
        for carb in carbData {
            let date = carb.date ?? Date()
            guard let glucose = MainChartHelper.timeToNearestGlucose(
                glucoseValues: glucoseData,
                time: date.timeIntervalSince1970
            )?.glucose else { continue }

            let displayValue = units == .mgdL ? Decimal(glucose) : Decimal(glucose).asMmolL
            guard let x = proxy.position(forX: date),
                  let y = proxy.position(forY: displayValue) else { continue }

            let barHeight = MainChartHelper.carbBarHeight(amount: Decimal(carb.carbs), maxAmount: maxCarbs)
            let totalHeight = MainChartHelper.Config.carbBarSpacing + barHeight + MainChartHelper.Config
                .carbAnnotationSpacing + Self.barLabelHeight
            rects.append(CGRect(
                x: x - max(MainChartHelper.Config.carbBarWidth, 14) / 2,
                y: y,
                width: max(MainChartHelper.Config.carbBarWidth, 14),
                height: totalHeight
            ))
        }

        return rects
    }

    // MARK: - Helpers

    private func peakColor(glucose: Decimal) -> Color {
        let hardCodedLow = Decimal(55)
        let hardCodedHigh = Decimal(220)
        let isDynamic = glucoseColorScheme == .dynamicColor

        return Trio.getDynamicGlucoseColor(
            glucoseValue: glucose,
            highGlucoseColorValue: isDynamic ? hardCodedHigh : highGlucose,
            lowGlucoseColorValue: isDynamic ? hardCodedLow : lowGlucose,
            targetGlucose: currentGlucoseTarget,
            glucoseColorScheme: glucoseColorScheme
        )
    }

    private func formattedGlucose(_ glucose: Int) -> String {
        glucose.formatted(for: units)
    }
}

/// Shared peak-label badge used by `PeakLabelsOverlay` for both highs and lows.
///
/// Light mode keeps the current high-contrast design (`.primary` text on a
/// tinted fill with a faint primary stroke). Dark mode uses the original
/// pre-bars design (colored text on a faint colored fill, no stroke).
struct PeakLabelBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String
    let color: Color

    var body: some View {
        if colorScheme == .dark {
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.15))
                )
        } else {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.primary.opacity(0.7), lineWidth: 0.4)
                )
        }
    }
}
