import SwiftUI

/// The window behind "About Medical".
///
/// The standard panel AppKit gives away for free lists a bundle identifier and
/// a copyright line, which is what a company wants said about its product. This
/// one says what the application is for and who wrote it, which is what a
/// person opening it actually wanted to know.
struct AboutView: View {
    @Environment(AppSettings.self) private var settings

    private static let repository = URL(string: "https://github.com/Ta2-me2")!

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                // The icon the owner chose, not a fixed one: this window is
                // where you come to look at the application, and it should be
                // the application you are looking at.
                if let icon = settings.icon.image {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 104, height: 104)
                }

                VStack(spacing: 5) {
                    Text("Medical")
                        .font(.system(size: 26, weight: .semibold))

                    Text("Version \(Self.version)")
                        .font(.callout)
                        .foregroundStyle(Palette.secondaryText)
                        .monospacedDigit()
                }

                Text("A personal medical archive. Every document you own, in one folder you own — plain files and readable JSON, on this Mac and nowhere else.")
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .padding(.top, 34)
            .padding(.bottom, 26)

            Divider()

            HStack(spacing: 10) {
                Image("AuthorLogo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30, height: 30)
                    .clipShape(.circle)
                    .overlay {
                        Circle().strokeBorder(Palette.separator, lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Ta2")
                        .font(.subheadline.weight(.medium))
                    Link("github.com/Ta2-me2", destination: Self.repository)
                        .font(.caption)
                }

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 16)
        }
        .frame(width: 380)
        .background(Palette.page)
    }

    /// Read from the bundle rather than written here, so the number in the
    /// window and the number in the build cannot drift apart.
    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
