import SwiftUI
import EventKit
import EventKitUI

struct CalendarEventRow: View {
    let event: CalendarEvent
    @State private var calendarAccessDenied = false
    @State private var addResult: AddResult?

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
                addToFJUCalendar()
            } label: {
                Label("加入行事曆", systemImage: "calendar.badge.plus")
            }
            .tint(.blue)
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
        .alert(
            addResult?.title ?? "",
            isPresented: Binding(get: { addResult != nil }, set: { if !$0 { addResult = nil } })
        ) {
            Button("確定", role: .cancel) { addResult = nil }
        } message: {
            Text(addResult?.message ?? "")
        }
    }

    private func addToFJUCalendar() {
        Task {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                guard granted else {
                    await MainActor.run { calendarAccessDenied = true }
                    return
                }
                let calendar = try fjuLocalCalendar()
                // Skip if duplicate already exists in FJU calendar
                let end = event.endDate ?? Foundation.Calendar.current.date(byAdding: .hour, value: 1, to: event.startDate) ?? event.startDate
                let predicate = eventStore.predicateForEvents(withStart: event.startDate, end: end, calendars: [calendar])
                let existing = eventStore.events(matching: predicate)
                if existing.contains(where: { $0.title == event.title }) {
                    await MainActor.run {
                        addResult = AddResult(title: "已存在", message: "「\(event.title)」已在「輔大行事曆」中。")
                    }
                    return
                }
                let ekEvent = makeEKEvent(calendar: calendar)
                try eventStore.save(ekEvent, span: .thisEvent)
                await MainActor.run {
                    addResult = AddResult(title: "已加入", message: "「\(event.title)」已加入「輔大行事曆」。")
                }
            } catch {
                await MainActor.run {
                    addResult = AddResult(title: "加入失敗", message: error.localizedDescription)
                }
            }
        }
    }

    private func fjuLocalCalendar() throws -> EKCalendar {
        let name = "輔大行事曆"
        if let existing = eventStore.calendars(for: .event).first(where: { $0.title == name }) {
            return existing
        }
        let source = eventStore.sources.first(where: { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") })
            ?? eventStore.sources.first(where: { $0.sourceType == .local })
            ?? eventStore.sources.first(where: { !$0.calendars(for: .event).isEmpty })
            ?? eventStore.defaultCalendarForNewEvents?.source
        guard let source else { throw CalendarError.noSource }
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = name
        calendar.source = source
        calendar.cgColor = UIColor.systemBlue.cgColor
        try eventStore.saveCalendar(calendar, commit: true)
        return calendar
    }

    private func makeEKEvent(calendar: EKCalendar) -> EKEvent {
        let ekEvent = EKEvent(eventStore: eventStore)
        ekEvent.title = event.title
        ekEvent.startDate = event.startDate
        ekEvent.endDate = event.endDate ?? Foundation.Calendar.current.date(byAdding: .hour, value: 1, to: event.startDate) ?? event.startDate
        ekEvent.notes = event.description
        ekEvent.calendar = calendar
        let components = Foundation.Calendar.current.dateComponents([.hour, .minute], from: event.startDate)
        if components.hour == 0 && components.minute == 0 {
            ekEvent.isAllDay = true
        }
        return ekEvent
    }

    private enum CalendarError: LocalizedError {
        case noSource
        var errorDescription: String? { "找不到可用的行事曆來源。" }
    }

    private struct AddResult {
        let title: String
        let message: String
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
