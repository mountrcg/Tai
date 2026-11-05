import SwiftUI

extension Main {
    struct LoadingView: View {
        @Binding var showError: Bool
        let retry: () -> Void

        private let versionNumber = Bundle.main.releaseVersionNumber ?? String(localized: "Unknown")
        private let buildNumber = Bundle.main.buildVersionNumber ?? String(localized: "Unknown")
        private let copyright = Bundle.main.copyRightNotice ?? "Unknown"

        var body: some View {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color.bgDarkBlue, Color.bgDarkerDarkBlue]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack {
                    Spacer().frame(maxHeight: 92)

                    Image(.taiCircledNoBackground)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 92, height: 92)
                        .shadow(color: Color.white.opacity(0.1), radius: 5, x: 0, y: 0)

                    Text("Tai v\(versionNumber) (\(buildNumber)) \(copyright)")
                        .fontWeight(.heavy)
                        .foregroundStyle(Color.uam)
                        .padding(.vertical)

                    if showError {
                        Spacer().frame(maxHeight: 60)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Oops, there was an issue!").font(.title3).bold()

                            Text("Something went wrong while loading your data. Please try again in a few moments.")
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 24)
                        .foregroundStyle(.white)

                        Spacer()

                        RetryButton(action: retry).padding(.bottom, 60)
                    } else {
                        Spacer().frame(maxHeight: 100)

                        CustomProgressView(text: String(localized: "Getting everything ready for you...")).foregroundStyle(.white)

                        Spacer()
                    }
                }
            }
        }
    }

    struct RetryButton: View {
        var action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .containerRelativeFrame(.horizontal) { width, _ in width - 60 }
                .frame(height: 50)
                .font(.title3).bold()
                .background(
                    Capsule()
                        .fill(Color.blue)
                )
                .foregroundColor(Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            }
        }
    }
}

struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            Main.LoadingView(showError: .constant(false), retry: {})
                .previewDisplayName("Loading")
            Main.LoadingView(showError: .constant(true), retry: {})
                .previewDisplayName("Error")
        }
    }
}
