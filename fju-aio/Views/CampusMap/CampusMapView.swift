import SwiftUI
import MapKit
import CoreLocation

// CampusAmenity is defined in CampusBuilding.swift

private extension CampusAmenity.Category {
    var color: Color {
        switch self {
        case .foodCourt: return Color(hex: "#C2410C")
        case .convenienceStore: return Color(hex: "#0F766E")
        }
    }
}

// MARK: - Campus Map View

struct CampusMapView: View {
    /// When set, the map will fly to and highlight this building on appear.
    var highlightLocation: String? = nil

    @Environment(\.fjuService) private var service
    @AppStorage("preferredMapsApp") private var preferredMapsApp = "apple"

    private let buildings = CampusBuildingRegistry.all
    private let amenities = CampusAmenity.all

    @State private var searchText = ""
    @State private var selectedBuilding: CampusBuilding?
    @State private var selectedAmenity: CampusAmenity?
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
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return buildings }
        return buildings.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredAmenities: [CampusAmenity] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return amenities }
        return amenities.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.category.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var currentCourseBuilding: CampusBuilding? {
        guard let course = currentCourse else { return nil }
        return CampusBuildingRegistry.building(for: course.location)
    }

    private var locationButtonTopPadding: CGFloat {
        searchText.isEmpty ? 72 : 360
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition) {
                UserAnnotation()
                ForEach(filteredBuildings) { building in
                    Annotation(building.name, coordinate: building.coordinate, anchor: .bottom) {
                        BuildingPin(
                            building: building,
                            courseCount: coursesForBuilding(building).count,
                            isSelected: selectedBuilding?.id == building.id,
                            isCurrentClass: currentCourseBuilding?.id == building.id
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4)) {
                                selectedBuilding = building
                                selectedAmenity = nil
                                searchText = ""
                                fly(to: building.coordinate)
                            }
                        }
                    }
                }

                ForEach(filteredAmenities) { amenity in
                    Annotation(amenity.name, coordinate: amenity.coordinate, anchor: .bottom) {
                        AmenityPin(
                            amenity: amenity,
                            isSelected: selectedAmenity?.id == amenity.id
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4)) {
                                selectedAmenity = amenity
                                selectedBuilding = nil
                                searchText = ""
                                fly(to: amenity.coordinate)
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControlVisibility(.hidden)
            .ignoresSafeArea(edges: .bottom)

            // Search bar + results overlay
            SearchOverlay(
                searchText: $searchText,
                filteredBuildings: filteredBuildings,
                filteredAmenities: filteredAmenities,
                onSelect: { building in
                    withAnimation(.spring(response: 0.4)) {
                        selectedBuilding = building
                        selectedAmenity = nil
                        searchText = ""
                        fly(to: building.coordinate)
                    }
                },
                onSelectAmenity: { amenity in
                    withAnimation(.spring(response: 0.4)) {
                        selectedAmenity = amenity
                        selectedBuilding = nil
                        searchText = ""
                        fly(to: amenity.coordinate)
                    }
                }
            )

            // User location button, kept below the search overlay.
            VStack {
                HStack(alignment: .top) {
                    Spacer()

                    VStack(spacing: 10) {
                        Button {
                            locationManager.requestWhenInUseAuthorization()
                            cameraPosition = .userLocation(
                                followsHeading: false,
                                fallback: .region(MKCoordinateRegion(
                                    center: CLLocationCoordinate2D(latitude: 25.0360, longitude: 121.4320),
                                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                                ))
                            )
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .foregroundStyle(.blue)
                        .modifier(GlassOrMaterialBackground(cornerRadius: 14))
                        .accessibilityLabel("定位目前位置")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, locationButtonTopPadding)
                Spacer()
            }
            .animation(.spring(response: 0.3), value: locationButtonTopPadding)

            if let building = selectedBuilding {
                VStack {
                    Spacer()
                    BuildingDetailCard(
                        building: building,
                        courses: coursesForBuilding(building),
                        isCurrentClassBuilding: currentCourseBuilding?.id == building.id,
                        onNavigate: { openNavApp(building: building) },
                        onClose: {
                            withAnimation(.spring(response: 0.3)) {
                                selectedBuilding = nil
                            }
                        }
                    )
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            } else if let amenity = selectedAmenity {
                VStack {
                    Spacer()
                    AmenityDetailCard(
                        amenity: amenity,
                        onNavigate: { openNavApp(name: amenity.name, coordinate: amenity.coordinate) },
                        onClose: {
                            withAnimation(.spring(response: 0.3)) {
                                selectedAmenity = nil
                            }
                        }
                    )
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            } else if let course = currentCourse {
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
                    .frame(maxWidth: 520)
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

    private func coursesForBuilding(_ building: CampusBuilding) -> [Course] {
        courses.filter { CampusBuildingRegistry.building(for: $0.location)?.id == building.id }
            .sorted { lhs, rhs in
                if lhs.dayOfWeekNumber != rhs.dayOfWeekNumber {
                    return lhs.dayOfWeekNumber < rhs.dayOfWeekNumber
                }
                if lhs.startPeriod != rhs.startPeriod {
                    return lhs.startPeriod < rhs.startPeriod
                }
                return lhs.name < rhs.name
            }
    }

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

    private func openNavApp(building: CampusBuilding) {
        openNavApp(name: building.name, coordinate: building.coordinate)
    }

    private func openNavApp(name: String, coordinate: CLLocationCoordinate2D) {
        if preferredMapsApp == "google", let url = googleMapsURL(coordinate: coordinate),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            openAppleMaps(name: name, coordinate: coordinate)
        }
    }

    private func openAppleMaps(name: String, coordinate: CLLocationCoordinate2D) {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }

    private func googleMapsURL(coordinate: CLLocationCoordinate2D) -> URL? {
        let lat = coordinate.latitude
        let lng = coordinate.longitude
        return URL(string: "comgooglemaps://?daddr=\(lat),\(lng)&directionsmode=walking&zoom=17")
    }
}

// MARK: - Search Overlay

private struct SearchOverlay: View {
    @Binding var searchText: String
    let filteredBuildings: [CampusBuilding]
    let filteredAmenities: [CampusAmenity]
    let onSelect: (CampusBuilding) -> Void
    let onSelectAmenity: (CampusAmenity) -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                searchContent
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        } else {
            searchContent
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity, alignment: .center)
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
            TextField("搜尋建築、餐廳、商店...", text: $searchText)
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

                if !filteredBuildings.isEmpty && !filteredAmenities.isEmpty {
                    Divider()
                }

                ForEach(filteredAmenities) { amenity in
                    Button {
                        onSelectAmenity(amenity)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(amenity.category.color)
                                    .frame(width: 36, height: 36)
                                Image(systemName: amenity.category.iconName)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(amenity.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(amenity.category.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(amenity.note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    if amenity.id != filteredAmenities.last?.id {
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

// MARK: - Building Detail Card

private struct BuildingDetailCard: View {
    let building: CampusBuilding
    let courses: [Course]
    let isCurrentClassBuilding: Bool
    let onNavigate: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isCurrentClassBuilding ? Color.orange : Color.blue)
                        .frame(width: 44, height: 44)
                    Text(building.code)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(building.name)
                        .font(.headline)
                    Text(courses.isEmpty ? "尚無你的課程" : "\(courses.count) 門課在這棟建築")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("關閉建築詳細資訊")
            }

            HStack(spacing: 10) {
                if #available(iOS 26.0, *) {
                    Button(action: onNavigate) {
                        Label("導航", systemImage: "figure.walk")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    Button(action: onNavigate) {
                        Label("導航", systemImage: "figure.walk")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                }
            }

            if !courses.isEmpty {
                Divider()
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(courses) { course in
                            CourseRow(course: course)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(16)
        .modifier(GlassOrMaterialBackground(cornerRadius: 18))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}

private struct CourseRow: View {
    let course: Course

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: course.color))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(course.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(course.scheduleDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(course.location)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !course.instructor.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                        Text(course.instructor)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Amenity Detail Card

private struct AmenityDetailCard: View {
    let amenity: CampusAmenity
    let onNavigate: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(amenity.category.color)
                        .frame(width: 44, height: 44)
                    Image(systemName: amenity.category.iconName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(amenity.name)
                        .font(.headline)
                    Text(amenity.category.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("關閉地點詳細資訊")
            }

            Text(amenity.note)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if #available(iOS 26.0, *) {
                Button(action: onNavigate) {
                    Label("導航", systemImage: "figure.walk")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glassProminent)
            } else {
                Button(action: onNavigate) {
                    Label("導航", systemImage: "figure.walk")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(amenity.category.color, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(16)
        .modifier(GlassOrMaterialBackground(cornerRadius: 18))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
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
    let courseCount: Int
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

                if courseCount > 0 {
                    Text("\(courseCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 19, minHeight: 19)
                        .background(Color.red, in: Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .offset(x: 16, y: -16)
                        .accessibilityLabel("\(courseCount) 門課")
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

// MARK: - Amenity Pin

private struct AmenityPin: View {
    let amenity: CampusAmenity
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(amenity.category.color)
                    .frame(width: isSelected ? 42 : 34, height: isSelected ? 42 : 34)
                    .shadow(radius: isSelected ? 6 : 3)
                Image(systemName: amenity.category.iconName)
                    .font(.system(size: isSelected ? 17 : 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            Triangle()
                .fill(amenity.category.color)
                .frame(width: 10, height: 6)
        }
        .animation(.spring(response: 0.3), value: isSelected)
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
