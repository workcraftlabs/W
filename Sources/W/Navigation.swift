import SwiftUI
import WCore

enum WNavigation: String, CaseIterable, Identifiable {
    case tasks, history, notes, journal, settings
    var id: String { rawValue }
    var title: String { switch self { case .tasks: return "Tasks"; case .history: return "History"; case .notes: return "Notes"; case .journal: return "Journal"; case .settings: return "Settings" } }
    var icon: String { switch self { case .tasks: return "checkmark.square"; case .history: return "clock.arrow.circlepath"; case .notes: return "note.text"; case .journal: return "book.closed"; case .settings: return "slider.horizontal.3" } }
}
struct WSidebar: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(spacing: 10) {
            ForEach(WNavigation.allCases) { item in
                if item == .settings { Spacer() }
                Button { store.compact = false; store.navigation = item } label: {
                    Image(systemName: item.icon).font(.system(size: 15, weight: .regular))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(store.navigation == item ? Color.primary : .secondary)
                        .background(store.navigation == item ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).help(item.title).accessibilityLabel(item.title)
                    .accessibilityAddTraits(store.navigation == item ? .isSelected : [])
            }
        }.padding(.vertical, 22).frame(width: 48)
    }
}
struct CompletionHistoryView: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("History").font(.custom("Inter", size: 26)).fontWeight(.medium)
            Text("Completed in W · newest first").font(.custom("Inter", size: 11)).foregroundStyle(.secondary)
            let sessions = CompletionHistory.latest(store.state.sessions)
            if sessions.isEmpty {
                Text("Completed tasks will appear here.").foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(sessions) { session in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark").font(.system(size: 11)).foregroundStyle(.secondary)
                                    TaskTitleView(task: session.task, compact: true)
                                    Spacer(minLength: 0)
                                }
                                if let ended = session.endedAt {
                                    Text("\(ended.formatted(date: .abbreviated, time: .shortened)) · \(Int(session.accumulated / 60)) min")
                                        .font(.custom("Inter", size: 10)).foregroundStyle(.secondary)
                                }
                                if !session.task.project.isEmpty { Text(session.task.project).font(.custom("Inter", size: 10)).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
