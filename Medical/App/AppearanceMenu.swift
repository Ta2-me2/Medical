import SwiftUI

/// The small button beside the sidebar toggle: how the application looks, and
/// the way into About.
///
/// Not a Settings window. There is one preference here that is genuinely a
/// preference — light or dark — and putting it behind ⌘, alongside a window
/// with nothing else in it would be a heavier promise than the app can keep.
struct AppearanceMenu: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow

    @State private var isPresented = false

    var body: some View {
        @Bindable var settings = settings

        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .help("Appearance")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Appearance")
                        .font(.subheadline.weight(.semibold))

                    Picker("Appearance", selection: $settings.appearance) {
                        ForEach(AppSettings.Appearance.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("App Icon")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 12) {
                        ForEach(AppSettings.Icon.allCases) { choice in
                            iconButton(choice)
                        }
                        Spacer(minLength: 0)
                    }
                }

                Divider()

                Button("About Medical") {
                    isPresented = false
                    openWindow(id: AboutWindow.id)
                }
                .buttonStyle(.link)
            }
            .padding(16)
            .frame(width: 260)
        }
    }

    /// The icons are shown, not named: choosing between two pictures by reading
    /// the words "Light" and "Dark" is a step nobody needs.
    private func iconButton(_ choice: AppSettings.Icon) -> some View {
        let isSelected = settings.icon == choice

        return Button {
            settings.icon = choice
        } label: {
            Group {
                if let image = choice.image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Color.clear
                }
            }
            .frame(width: 54, height: 54)
            .padding(3)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Palette.selection : Palette.separator,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .help("\(choice.title) icon")
        .accessibilityLabel("\(choice.title) app icon")
    }
}

/// The About window's identity, in one place, so the menu bar and the popover
/// cannot open two different windows by disagreeing about a string.
enum AboutWindow {
    static let id = "about"
    static let title = "About Medical"
}
