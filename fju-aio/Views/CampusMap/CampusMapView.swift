import SwiftUI
import MapKit
import CoreLocation

// MARK: - Campus Map View

struct CampusMapView: View {
    /// When set, the map will fly to and highlight this building on appear.
    var highlightLocation: String? = nil

    @Environment(\.fjuService) private var service

    private let buildings = CampusBuildingRegistry.all

    @State private var searchText = ""
    @State private var selectedBuilding: CampusBuilding?
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.0360, longitude: 121.4320),
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        )
    )
    @State private var locationManager = CLLocationManager()
    @State private var courses: [Course] = []
    @State private var currentCourse: Course?

    private var filteredBuildings: [CampusBuilding] {
        if searchText.isEmpty { return buildings }
        return buildings.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var currentCourseBuilding: CampusBuilding? {
        guard let course = currentCourse else { return nil }
        return CampusBuildingRegistry.building(for: course.location)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition) {
                UserAnnotation()
                ForEach(filteredBuildings) { building in
                    Annotation(building.name, coordinate: building.coordinate, anchor: .bottom) {
                        BuildingPin(
                            building: building,
                            isSelected: selectedBuilding?.id == building.id,
                            isCurrentClass: currentCourseBuilding?.id == building.id
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4)) {
                                selectedBuilding = building
                                fly(to: building.coordinate)
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .bottom)

            // Search bar + results overlay
            SearchOverlay(
                searchText: $searchText,
                filteredBuildings: filteredBuildings,
                onSelect: { building in
                    withAnimation(.spring(response: 0.4)) {
                        selectedBuilding = building
                        searchText = ""
                        fly(to: building.coordinate)
                    }
                }
            )

            // Current class banner (bottom)
            if let course = currentCourse {
                VStack {
                    Spacer()
                    CurrentClassCard(course: course, buildingName: currentCourseBuilding?.name) {
                        if let b = currentCourseBuilding {
                            withAnimation(.spring(response: 0.4)) {
                                selectedBuilding = b
                                fly(to: b.coordinate)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("校園地圖")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if currentCourse != nil, let b = currentCourseBuilding {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.4)) {
                            selectedBuilding = b
                            fly(to: b.coordinate)
                        }
                    } label: {
                        Label("現在課程", systemImage: "location.fill")
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
        }
        .onAppear {
            locationManager.requestWhenInUseAuthorization()
            loadCoursesFromCache()
            if let location = highlightLocation,
               let building = CampusBuildingRegistry.building(for: location) {
                selectedBuilding = building
                fly(to: building.coordinate)
            }
        }
        .task {
            await refreshCoursesIfNeeded()
        }
    }

    // MARK: - Helpers

    private func fly(to coordinate: CLLocationCoordinate2D) {
        cameraPosition = .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
        ))
    }

    private func currentClassNow(from courses: [Course]) -> Course? {
        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let dayMap: [Int: String] = [2: "一", 3: "二", 4: "三", 5: "四", 6: "五"]
        guard let todayString = dayMap[weekday] else { return nil }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let currentTime = timeFormatter.string(from: now)

        return courses.first { course in
            guard course.dayOfWeek == todayString else { return false }
            guard course.startPeriod >= 1, course.endPeriod <= FJUPeriod.periodTimes.count else { return false }
            let start = FJUPeriod.periodTimes[course.startPeriod - 1].start
            let end   = FJUPeriod.periodTimes[course.endPeriod - 1].end
            return currentTime >= start && currentTime <= end
        }
    }

    @MainActor
    private func loadCoursesFromCache() {
        let cache = AppCache.shared
        guard let semesters = cache.getSemesters(), let semester = semesters.first,
              let cached = cache.getCourses(semester: semester) else { return }
        courses = cached
        currentCourse = currentClassNow(from: cached)
    }

    private func refreshCoursesIfNeeded() async {
        if !courses.isEmpty { return }
        do {
            let semesters = try await service.fetchAvailableSemesters()
            if let semester = semesters.first {
                let fetched = try await service.fetchCourses(semester: semester)
                await MainActor.run {
                    courses = fetched
                    currentCourse = currentClassNow(from: fetched)
                }
            }
        } catch {
            // Map is still usable without course data
        }
    }
}

// MARK: - Search Overlay

private struct SearchOverlay: View {
    @Binding var searchText: String
    let filteredBuildings: [CampusBuilding]
    let onSelect: (CampusBuilding) -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                searchContent
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        } else {
            searchContent
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        VStack(spacing: 8) {
            searchBar
            if !searchText.isEmpty {
                resultsDropdown
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜尋建築...", text: $searchText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .modifier(GlassOrMaterialBackground(cornerRadius: 14))
    }

    private var resultsDropdown: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(filteredBuildings) { building in
                    Button {
                        onSelect(building)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 36, height: 36)
                                Text(building.code)
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(building.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(building.code)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    if building.id != filteredBuildings.last?.id {
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .modifier(GlassOrMaterialBackground(cornerRadius: 14))
        }
        .frame(maxHeight: 280)
    }
}

// MARK: - Current Class Card

private struct CurrentClassCard: View {
    let course: Course
    let buildingName: String?
    let onLocate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label("現在上課", systemImage: "clock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(course.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(course.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if buildingName != nil {
                if #available(iOS 26.0, *) {
                    Button(action: onLocate) {
                        Label("定位", systemImage: "location.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .tint(.orange)
                } else {
                    Button(action: onLocate) {
                        Label("定位", systemImage: "location.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.orange, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            } else {
                Image(systemName: "mappin.slash")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .modifier(GlassOrMaterialBackground(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

// MARK: - Glass/Material Background Modifier

/// Applies Liquid Glass on iOS 26+, falls back to .regularMaterial on older OS.
private struct GlassOrMaterialBackground: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - Building Pin

private struct BuildingPin: View {
    let building: CampusBuilding
    let isSelected: Bool
    let isCurrentClass: Bool

    private var pinColor: Color {
        if isCurrentClass { return .orange }
        if isSelected { return .blue }
        return .green
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(pinColor)
                    .frame(width: (isSelected || isCurrentClass) ? 44 : 36,
                           height: (isSelected || isCurrentClass) ? 44 : 36)
                    .shadow(radius: (isSelected || isCurrentClass) ? 6 : 3)
                if isCurrentClass {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text(building.code)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                }
            }
            Triangle()
                .fill(pinColor)
                .frame(width: 10, height: 6)
        }
        .animation(.spring(response: 0.3), value: isSelected)
        .animation(.spring(response: 0.3), value: isCurrentClass)
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

#Preview {
    NavigationStack {
        CampusMapView()
            .environment(\.fjuService, FJUService.shared)
    }
}
