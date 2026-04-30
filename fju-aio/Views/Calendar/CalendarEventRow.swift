import SwiftUI
import EventKit
import EventKitUI

struct CalendarEventRow: View {
    let event: CalendarEvent
    @State private var showAddToCalendar = false
    @State private var calendarAccessDenied = false

    private let eventStore = EKEventStore()

    var body: some View {
        HStack(spacing: 12) {
            // Category color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(categoryColor)
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.body.weight(.medium))

                HStack(spacing: 6) {
                    Text(dateString)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(event.category.rawValue)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(categoryColor)
                        .background(categoryColor.opacity(0.12), in: Capsule())
                }

                if let desc = event.description {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                requestCalendarAccess()
            } label: {
                Label("加入行事曆", systemImage: "calendar.badge.plus")
            }
            .tint(.blue)
        }
        .sheet(isPresented: $showAddToCalendar) {
            EKEventEditViewWrapper(eventStore: eventStore, ekEvent: makeEKEvent())
        }
        .alert("無法存取行事曆", isPresented: $calendarAccessDenied) {
            Button("取消", role: .cancel) {}
            Button("前往設定") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("請在「設定」中允許存取行事曆。")
        }
    }

    private func requestCalendarAccess() {
        Task {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                await MainActor.run {
                    if granted {
                        showAddToCalendar = true
                    } else {
                        calendarAccessDenied = true
                    }
                }
            } catch {
                await MainActor.run {
                    calendarAccessDenied = true
                }
            }
        }
    }

    private func makeEKEvent() -> EKEvent {
        let ekEvent = EKEvent(eventStore: eventStore)
        ekEvent.title = event.title
        ekEvent.startDate = event.startDate
        ekEvent.endDate = event.endDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: event.startDate) ?? event.startDate
        ekEvent.notes = event.description
        ekEvent.calendar = eventStore.defaultCalendarForNewEvents
        // Mark as all-day if no specific time component
        let components = Calendar.current.dateComponents([.hour, .minute], from: event.startDate)
        if components.hour == 0 && components.minute == 0 {
            ekEvent.isAllDay = true
        }
        return ekEvent
    }

    private var categoryColor: Color {
        switch event.category {
        case .exam: return .red
        case .holiday: return .green
        case .registration: return .blue
        case .activity: return AppTheme.accent
        case .deadline: return .orange
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        let start = formatter.string(from: event.startDate)
        if let end = event.endDate {
            let endStr = formatter.string(from: end)
            return "\(start) - \(endStr)"
        }
        return start
    }
}

/// UIViewControllerRepresentable wrapper for EKEventEditViewController
struct EKEventEditViewWrapper: UIViewControllerRepresentable {
    let eventStore: EKEventStore
    let ekEvent: EKEvent
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = eventStore
        controller.event = ekEvent
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}
