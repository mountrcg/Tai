import CoreData
import SwiftDate
import SwiftUI
import UIKit

struct LoopView: View {
    @Environment(\.colorScheme) var colorScheme

    private enum Config {
        static let lag: TimeInterval = 30
    }

    let closedLoop: Bool
    let timerDate: Date
    let isLooping: Bool
    let lastLoopDate: Date
    let manualTempBasal: Bool

    let determination: [OrefDetermination]

    private let rect = CGRect(x: 0, y: 0, width: 18, height: 18)

    var body: some View {
        HStack(alignment: .center) {
            ZStack {
                if isLooping {
                    CircleProgress()
                } else {
                    Circle()
                        .strokeBorder(color, lineWidth: 3.2)
                        .frame(width: rect.width, height: rect.height, alignment: .center)
                        .mask(mask(in: rect).fill(style: FillStyle(eoFill: true)))
                }
            }
            if determination.first?
                .deliverAt !=
                nil
            {
                // previously the .timestamp property was used here because this only gets updated when the reportenacted function in the aps manager gets called
                Text(timeString)
            } else {
                Text("--")
            }
        }
        .font(.callout).fontWeight(.bold).fontDesign(.rounded)
        .foregroundColor(color)
    }

    private var timeString: String {
        let minutesAgo = TimeAgoFormatter.minutesAgoValue(from: lastLoopDate)
        if minutesAgo > 1440 {
            return "--"
        } else {
            return TimeAgoFormatter.minutesAgo(from: lastLoopDate)
        }
    }

    private var color: Color {
        guard determination.first?.deliverAt != nil
        else {
            // previously the .timestamp property was used here because this only gets updated when the reportenacted function in the aps manager gets called
            return .secondary
        }
        guard manualTempBasal == false else {
            return .loopManualTemp
        }
        guard closedLoop == true else {
            return .blue
        }

        let delta = timerDate.timeIntervalSince(lastLoopDate) - Config.lag

        if delta <= 5.minutes.timeInterval {
            guard determination.first?.timestamp != nil else {
                return .loopYellow
            }
            return .loopGreen
        } else if delta <= 10.minutes.timeInterval {
            return .loopYellow
        } else {
            return .loopRed
        }
    }

    func mask(in rect: CGRect) -> Path {
        var path = Rectangle().path(in: rect)
        if !closedLoop || manualTempBasal {
            path.addPath(Rectangle().path(in: CGRect(x: rect.minX, y: rect.midY - 2.5, width: rect.width, height: 5)))
        }
        return path
    }
}

struct CircleProgress: View {
    @State private var rotationAngle = 0.0
    @State private var pulse = false

    private let rect = CGRect(x: 0, y: 0, width: 16, height: 16) // Same dimensions as in LoopView
    private var backgroundGradient: AngularGradient {
        // Create a custom angular gradient based on TaiStyle colors but with custom rotation
        AngularGradient(
            stops: [
                .init(color: Color.orange, location: 0.0),
                .init(color: Color.teal, location: 0.3),
                .init(color: Color.cyan, location: 0.5),
                .init(color: Color.teal, location: 0.8),
                .init(color: Color.orange, location: 1.0)

            ],
            center: .center,
            startAngle: .degrees(rotationAngle),
            endAngle: .degrees(rotationAngle + 360)
        )
    }

    let timer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()

    var body: some View {
        let rect = CGRect(x: 0, y: 0, width: 18, height: 18)

        ZStack {
            Circle()
                .trim(from: 0, to: 1)
//                .stroke(backgroundGradient, style: StrokeStyle(lineWidth: 3))
                .stroke(backgroundGradient, style: StrokeStyle(lineWidth: pulse ? 6 : 3.2))
                .scaleEffect(pulse ? 0.5 : 1)
                .animation(
                    Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                    value: pulse
                )
                .frame(width: rect.width, height: rect.height, alignment: .center)
                .onReceive(timer) { _ in
                    rotationAngle = (rotationAngle + 24).truncatingRemainder(dividingBy: 360)
                }
                .onAppear {
                    self.pulse = true
                }
        }
    }
}

// extension View {
//    func animateForever(
//        using animation: Animation = Animation.easeInOut(duration: 1),
//        autoreverses: Bool = false,
//        _ action: @escaping () -> Void
//    ) -> some View {
//        let repeated = animation.repeatForever(autoreverses: autoreverses)
//
//        return onAppear {
//            withAnimation(repeated) {
//                action()
//            }
//        }
//    }
// }
