import SwiftUI
import MapKit

struct CourseDetailSheet: View {
    let course: Course
    var onOpenMap: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @AppStorage("preferredMapsApp") private var preferredMapsApp = "apple"

    private var matchedBuilding: CampusBuilding? {
        CampusBuildingRegistry.building(for: course.location)
    }

    var body: some View {
        NavigationStack {
            List {
                // Map section at the top — outside a Section so it has no inset padding
                if let building = matchedBuilding {
                    Section {
                        LocationMapSection(
                            building: building,
                            roomLabel: course.location,
                            onNavigate: { openNavApp(building: building) },
                            onOpenInAppMap: {
                                dismiss()
                                onOpenMap?()
                            }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

                // Course info
                Section {
                    LabeledContent("課程名稱", value: course.name)
                    LabeledContent("授課教師", value: course.instructor)
                    if !course.code.isEmpty {
                        LabeledContent("課程代碼", value: course.code)
                    }
                }

                Section {
                    LabeledContent("上課時間", value: course.scheduleDescription)
                    LabeledContent("上課地點", value: course.location)
                    if course.credits > 0 {
                        LabeledContent("學分", value: "\(course.credits)")
                    }
                    if course.courseType != .unknown {
                        LabeledContent("類別", value: course.courseType.rawValue == "必" ? "必修" : "選修")
                    }
                }

                if !course.department.isEmpty {
                    Section {
                        LabeledContent("開課系所", value: course.department)
                    }
                }

                if let notes = course.notes, !notes.isEmpty {
                    Section("備註") {
                        Text(notes)
                            .font(.subheadline)
                    }
                }

                if let outline = course.outline, outline.hasContent {
                    if let objective = outline.objective {
                        Section("課程目標") {
                            Text(objective)
                                .font(.subheadline)
                        }
                    }

                    if !outline.weeklyPlans.isEmpty {
                        Section("課程進度") {
                            ForEach(outline.weeklyPlans) { plan in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("第 \(plan.week) 週")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    if !plan.title.isEmpty {
                                        Text(plan.title)
                                            .font(.subheadline)
                                    }

                                    if let other = plan.other {
                                        Text(other)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }

                    if outline.teachingMaterials != nil ||
                        outline.textbook != nil ||
                        outline.referenceBook != nil {
                        Section("教材") {
                            if let teachingMaterials = outline.teachingMaterials {
                                DetailTextRow(label: "授課教材", value: teachingMaterials)
                            }
                            if let textbook = outline.textbook {
                                DetailTextRow(label: "教科書", value: textbook)
                            }
                            if let referenceBook = outline.referenceBook {
                                DetailTextRow(label: "參考書", value: referenceBook)
                            }
                        }
                    }

                    if outline.policies != nil ||
                        outline.otherNotes != nil ||
                        outline.contact != nil ||
                        outline.officeHours != nil ||
                        outline.externalURL != nil {
                        Section("其他資訊") {
                            if let policies = outline.policies {
                                DetailTextRow(label: "課程規範", value: policies)
                            }
                            if let otherNotes = outline.otherNotes {
                                DetailTextRow(label: "補充說明", value: otherNotes)
                            }
                            if let contact = outline.contact {
                                DetailTextRow(label: "聯絡方式", value: contact)
                            }
                            if let officeHours = outline.officeHours {
                                DetailTextRow(label: "Office Hours", value: officeHours)
                            }
                            if let urlString = outline.externalURL,
                               let url = URL(string: urlString) {
                                Link("開啟完整課綱", destination: url)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("課程資訊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: - Helpers

    private func openNavApp(building: CampusBuilding) {
        if preferredMapsApp == "google", let url = googleMapsURL(building: building),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            openAppleMaps(building: building)
        }
    }

    private func openAppleMaps(building: CampusBuilding) {
        let placemark = MKPlacemark(coordinate: building.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "\(building.name) – \(course.location)"
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }

    private func googleMapsURL(building: CampusBuilding) -> URL? {
        let lat = building.coordinate.latitude
        let lng = building.coordinate.longitude
        return URL(string: "comgooglemaps://?daddr=\(lat),\(lng)&directionsmode=walking&zoom=17")
    }
}

private struct DetailTextRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Location Map Section

private struct LocationMapSection: View {
    let building: CampusBuilding
    let roomLabel: String
    let onNavigate: () -> Void
    let onOpenInAppMap: () -> Void

    @State private var position: MapCameraPosition

    init(building: CampusBuilding, roomLabel: String, onNavigate: @escaping () -> Void, onOpenInAppMap: @escaping () -> Void) {
        self.building = building
        self.roomLabel = roomLabel
        self.onNavigate = onNavigate
        self.onOpenInAppMap = onOpenInAppMap
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: building.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
        )))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Non-interactive map preview
            Map(position: $position) {
                Annotation(building.name, coordinate: building.coordinate, anchor: .bottom) {
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 36, height: 36)
                                .shadow(radius: 3)
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Triangle()
                            .fill(Color.blue)
                            .frame(width: 10, height: 6)
                    }
                }
            }
            .mapStyle(.standard)
            .mapControls { }
            .frame(height: 180)
            .allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Building name + room
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(building.name)
                        .font(.subheadline.weight(.semibold))
                    Text(roomLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.top, 12)
            .padding(.horizontal, 16)

            // Action buttons
            if #available(iOS 26.0, *) {
                HStack(spacing: 10) {
                    Button(action: onOpenInAppMap) {
                        Label("在校園地圖中查看", systemImage: "map.fill")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.glass)

                    Button(action: onNavigate) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                            Text("導航")
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(.glassProminent)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)
            } else {
                HStack(spacing: 10) {
                    Button(action: onOpenInAppMap) {
                        Label("在校園地圖中查看", systemImage: "map.fill")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(OutlineButtonStyle())

                    Button(action: onNavigate) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                            Text("導航")
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(FilledButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
        }
    }
}

// MARK: - Button Styles

private struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct FilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Triangle Shape

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
