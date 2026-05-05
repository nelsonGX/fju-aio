import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - Shared display helper
//
// IMPORTANT: TimelineView and computed strings do NOT update continuously in
// Live Activity / WidgetKit contexts — the system controls render cadence.
// For any live-updating text, ONLY use SwiftUI's built-in Text date styles
// (`.timer`, `.relative`, or the `timerInterval:` string interpolation),
// which the OS renders natively and keeps live without app involvement.

private struct CourseActivityDisplay {
    let phase: CoursePhase
    let timerTarget: Date

    init(context: ActivityViewContext<CourseActivityAttributes>, now: Date) {
        if now >= context.state.classEndDate || context.state.phase == .ended {
            phase = .ended
            timerTarget = context.state.classEndDate
        } else if now >= context.state.classStartDate {
            phase = .during
            timerTarget = context.state.classEndDate
        } else {
            phase = .before
            timerTarget = context.state.classStartDate
        }
    }

    var accentColor: Color {
        switch phase {
        case .before: Color(red: 1.0, green: 0.62, blue: 0.0)   // vivid amber
        case .during: Color(red: 0.35, green: 0.78, blue: 1.0)  // sky blue
        case .ended:  Color(red: 0.3,  green: 0.9,  blue: 0.5)  // mint green
        }
    }

    var phaseIcon: String {
        switch phase {
        case .before: "clock.fill"
        case .during: "book.fill"
        case .ended:  "checkmark.circle.fill"
        }
    }

    var phaseLabel: String {
        switch phase {
        case .before: "距離上課"
        case .during: "距離下課"
        case .ended:  "課程結束"
        }
    }
}

// MARK: - Lock Screen / Banner

struct CourseLiveActivityView: View {
    let context: ActivityViewContext<CourseActivityAttributes>

    var body: some View {
        // Static snapshot — phase is computed once at render time.
        // The timer text inside stays live because it uses Text date styles.
        let display = CourseActivityDisplay(context: context, now: .now)

        VStack(alignment: .leading, spacing: 9) {
            // Top row: icon + course name/location + live timer
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: display.phaseIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(display.accentColor)
                    .frame(width: 40, height: 40)
                    .background(display.accentColor.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.courseName)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 3) {
                        Image(systemName: "mappin")
                            .font(.system(size: 10, weight: .medium))
                        Text(context.attributes.location)
                            .font(.system(.caption, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 0)

                if display.phase == .ended {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(display.accentColor)
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(display.phaseLabel)
                            .font(.system(.caption2, weight: .medium))
                            .foregroundStyle(.secondary)
                        // Full hh:mm:ss — live, system-rendered
                        Text(display.timerTarget, style: .timer)
                            .font(.system(.title3, design: .rounded).monospacedDigit().bold())
                            .foregroundStyle(display.accentColor)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            // Bottom row: instructor + map link
            HStack(alignment: .center, spacing: 0) {
                Label(context.attributes.instructor, systemImage: "person.circle")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if display.phase != .ended, let mapURL = context.attributes.mapURL {
                    Link(destination: mapURL) {
                        Label("在地圖中查看", systemImage: "map.fill")
                            .font(.system(.caption, weight: .semibold))
                            .foregroundStyle(display.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(display.accentColor.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .widgetURL(context.attributes.courseDetailURL)
    }
}

// MARK: - Dynamic Island: Compact Leading

/// Before class: shows the classroom name — most useful info when heading to class.
/// During / ended: phase icon.
struct CourseCompactLeading: View {
    let context: ActivityViewContext<CourseActivityAttributes>

    var body: some View {
        let display = CourseActivityDisplay(context: context, now: .now)
        Group {
            if display.phase == .before {
                Text(context.attributes.location)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(display.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 48)
            } else {
                Image(systemName: display.phaseIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(display.accentColor)
            }
        }
        .widgetURL(context.attributes.courseDetailURL)
    }
}

// MARK: - Dynamic Island: Compact Trailing

/// Live countdown using `timerInterval` string interpolation with `showsHours: false`
/// so it shows mm:ss (max ~5 chars) when under 1 hour, keeping the slot narrow.
/// When ≥ 1 hour it shows h:mm — still compact at 4 chars.
/// This is system-rendered and updates continuously without TimelineView.
struct CourseCompactTrailing: View {
    let context: ActivityViewContext<CourseActivityAttributes>

    var body: some View {
        let display = CourseActivityDisplay(context: context, now: .now)
        Group {
            if display.phase == .ended {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(display.accentColor)
            } else {
                Text(
                    timerInterval: Date.now ... display.timerTarget,
                    pauseTime: nil,
                    countsDown: true,
                    showsHours: true
                )
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(display.accentColor)
                .lineLimit(1)
                .frame(maxWidth: 48, alignment: .trailing)
                .minimumScaleFactor(0.8)
            }
        }
        .widgetURL(context.attributes.courseDetailURL)
    }
}

// MARK: - Dynamic Island: Expanded

struct CourseExpandedLeading: View {
    let context: ActivityViewContext<CourseActivityAttributes>

    var body: some View {
        let display = CourseActivityDisplay(context: context, now: .now)
        VStack(alignment: .leading, spacing: 3) {
            Text(context.attributes.courseName)
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 3) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(context.attributes.location)
                    .font(.system(.caption2, weight: .semibold))
            }
            .foregroundStyle(display.accentColor)
            .lineLimit(1)
        }
        .padding(.leading, 4)
        .widgetURL(context.attributes.courseDetailURL)
    }
}

struct CourseExpandedTrailing: View {
    let context: ActivityViewContext<CourseActivityAttributes>

    var body: some View {
        let display = CourseActivityDisplay(context: context, now: .now)
        VStack(alignment: .trailing, spacing: 2) {
            if display.phase == .ended {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(display.accentColor)
            } else {
                Text(display.phaseLabel)
                    .font(.system(.caption2, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))

                // Full hh:mm:ss — expanded has plenty of room
                Text(display.timerTarget, style: .timer)
                    .font(.system(.title3, design: .rounded).monospacedDigit().bold())
                    .foregroundStyle(display.accentColor)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.trailing, 4)
        .widgetURL(context.attributes.courseDetailURL)
    }
}

struct CourseExpandedBottom: View {
    let context: ActivityViewContext<CourseActivityAttributes>

    var body: some View {
        let display = CourseActivityDisplay(context: context, now: .now)
        HStack(alignment: .center, spacing: 0) {
            Label(context.attributes.instructor, systemImage: "person.circle.fill")
                .font(.system(.caption2, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)

            Spacer(minLength: 8)

            if display.phase != .ended, let mapURL = context.attributes.mapURL {
                Link(destination: mapURL) {
                    Label("在地圖中查看", systemImage: "map.fill")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(display.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(display.accentColor.opacity(0.2), in: Capsule())
                }
            } else if display.phase == .ended {
                Text("課程已結束")
                    .font(.system(.caption2, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }
}

// MARK: - Dynamic Island: Minimal

/// Minimal (detached oval) — shows ??小時, e.g. "1小時".
/// Static text is fine: it only needs to update hourly, which matches the system render cadence.
struct CourseMinimalView: View {
    let context: ActivityViewContext<CourseActivityAttributes>

    var body: some View {
        let display = CourseActivityDisplay(context: context, now: .now)
        Group {
            if display.phase == .ended {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(display.accentColor)
            } else {
                let secsRemaining = max(0, display.timerTarget.timeIntervalSinceNow)
                let hours = Int(secsRemaining / 3600)
                if hours >= 1 {
                    // Static Chinese hours — only needs to update hourly
                    Text("\(hours)小時")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(display.accentColor)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                } else {
                    // Live mm:ss — system-rendered, stays accurate every second
                    Text(
                        timerInterval: Date.now ... display.timerTarget,
                        pauseTime: nil,
                        countsDown: true,
                        showsHours: false
                    )
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(display.accentColor)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                }
            }
        }
        .widgetURL(context.attributes.courseDetailURL)
    }
}
