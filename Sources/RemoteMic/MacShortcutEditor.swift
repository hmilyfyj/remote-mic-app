import SwiftUI

struct MacShortcutEditor: View {
    @ObservedObject var service: MacShortcutsService
    @ObservedObject var localization: LocalizationStore
    let selected: MacShortcut?
    let onSelect: (MacShortcut?) -> Void
    @State private var search = ""

    private var matches: [MacShortcut] {
        service.shortcuts.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localization.text("action.run_mac_shortcut"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { Task { await service.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(localization.text("mac_shortcuts.refresh"))
                .disabled(service.isLoading)
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .help(localization.text("mac_shortcuts.open"))
            }
            TextField(localization.text("mac_shortcuts.search"), text: $search)
                .textFieldStyle(.roundedBorder)
            if service.isLoading {
                ProgressView().controlSize(.small)
            }
            if let error = service.listError {
                Text(localization.text(error)).foregroundStyle(.orange)
            } else if service.hasLoaded && service.shortcuts.isEmpty {
                Text(localization.text("mac_shortcuts.empty")).foregroundStyle(.secondary)
            } else if service.hasLoaded && matches.isEmpty {
                Text(localization.text("mac_shortcuts.no_matches")).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(matches) { shortcut in
                        Button { onSelect(shortcut) } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: selected?.id == shortcut.id ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(selected?.id == shortcut.id ? Color.accentColor : .secondary)
                                Text(shortcut.name).multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected?.id == shortcut.id ? .isSelected : [])
                    }
                }
            }
            .frame(height: 160)
            Divider()
            if let selected {
                HStack(alignment: .top) {
                    Text(service.shortcuts.first(where: { $0.id == selected.id })?.name ?? selected.name)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { service.run(selected) } label: { Image(systemName: "play.fill") }
                        .help(localization.text("mac_shortcuts.run"))
                        .disabled(service.states[selected.id] == .running)
                    Button { onSelect(nil) } label: { Image(systemName: "xmark") }
                        .help(localization.text("mac_shortcuts.clear"))
                }
                if service.hasLoaded && service.listError == nil && !service.shortcuts.contains(where: { $0.id == selected.id }) {
                    Text(localization.text("mac_shortcuts.missing")).foregroundStyle(.orange)
                }
                if let state = service.states[selected.id] {
                    Text(localization.text(state.localizationKey))
                        .foregroundStyle(state == .failed || state == .timedOut || state == .unavailable ? Color.orange : .secondary)
                }
            } else {
                Text(localization.text("mac_shortcuts.choose")).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .fixedSize(horizontal: false, vertical: true)
        .task { if !service.hasLoaded { await service.refresh() } }
        .onChange(of: service.shortcuts) { shortcuts in
            if let selected, let current = shortcuts.first(where: { $0.id == selected.id }), current != selected {
                onSelect(current)
            }
        }
    }
}
