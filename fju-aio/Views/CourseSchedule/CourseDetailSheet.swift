import SwiftUI
import MapKit

struct CourseDetailSheet: View {
    let course: Course
    var onOpenMap: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationManager.self) private var authManager
    @AppStorage("preferredMapsApp") private var preferredMapsApp = "apple"
    @AppStorage("myProfile.isPublished") private var isMyProfilePublished = false

    @State private var enrollments: [Enrollment] = []
    @State private var avatars: [String: String] = [:]
    @State private var enrollmentsLoading = false
    @State private var publicProfilesByEmpNo: [String: PublicProfile] = [:]

    // Friend data for badge display
    private var friendStore: FriendStore { FriendStore.shared }
    /// empNos of friends who have published a profile (cloudKit record exists locally)
    private var friendEmpNos: Set<String> { Set(friendStore.friends.map(\.empNo)) }

    private var matchedBuilding: CampusBuilding? {
        CampusBuildingRegistry.building(for: course.location)
    }

    var body: some View {
        NavigationStack {
            List {
                // Map section
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

                // Enrollment preview bar — navigates to full list
                Section {
                    NavigationLink {
                        EnrollmentListView(
                            enrollments: enrollments,
                            avatars: avatars,
                            isLoading: enrollmentsLoading,
                            friendEmpNos: friendEmpNos,
                            publicProfilesByEmpNo: publicProfilesByEmpNo
                        )
                    } label: {
                        EnrollmentPreviewBar(
                            enrollments: enrollments,
                            avatars: avatars,
                            isLoading: enrollmentsLoading,
                            friendEmpNos: friendEmpNos
                        )
                    }
                } header: {
                    Text("修課名單")
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
            .task {
                await loadEnrollments()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: - Helpers

    @MainActor
    private func loadEnrollments() async {
        var hasCachedEnrollments = false
        if let cached = await TronClassAPIService.shared.cachedEnrollments(courseCode: course.code) {
            enrollments = cached.0
            avatars = cached.1
            hasCachedEnrollments = !cached.0.isEmpty
            loadCachedPublicProfiles(for: cached.0)
        }

        enrollmentsLoading = !hasCachedEnrollments
        do {
            let (list, avatarMap) = try await TronClassAPIService.shared.getEnrollments(courseCode: course.code)
            enrollments = list
            avatars = avatarMap
            enrollmentsLoading = false
            loadCachedPublicProfiles(for: list)
            await refreshPublicProfiles(for: list)
        } catch {
            // Silently ignore — preview bar shows empty state
        }
        enrollmentsLoading = false
    }

    @MainActor
    private func loadCachedPublicProfiles(for enrollments: [Enrollment]) {
        let studentEmpNos = enrollments
            .filter { $0.primaryRole == .student }
            .map(\.user.user_no)
            .filter { !$0.isEmpty }

        let cached = PublicProfileCache.shared.profiles(for: studentEmpNos)
        if !cached.isEmpty {
            publicProfilesByEmpNo = cached
        }
    }

    @MainActor
    private func refreshPublicProfiles(for enrollments: [Enrollment]) async {
        let studentEmpNos = enrollments
            .filter { $0.primaryRole == .student }
            .map(\.user.user_no)
            .filter { !$0.isEmpty }

        let cached = PublicProfileCache.shared.profiles(for: studentEmpNos)

        do {
            var profiles = try await CloudKitProfileService.shared.fetchProfiles(empNos: studentEmpNos)
            if isMyProfilePublished,
               let session = try? await authManager.getValidSISSession(),
               studentEmpNos.contains(session.empNo),
               let ownProfile = try? await CloudKitProfileService.shared.fetchProfile(recordName: ProfileQRService.stableDeviceToken()) {
                profiles.append(ownProfile)
            }
            publicProfilesByEmpNo = profiles.reduce(into: [:]) { result, profile in
                if let existing = result[profile.empNo],
                   existing.lastUpdated >= profile.lastUpdated {
                    return
                }
                result[profile.empNo] = profile
            }
            PublicProfileCache.shared.store(Array(publicProfilesByEmpNo.values))
        } catch {
            if cached.isEmpty {
                publicProfilesByEmpNo = [:]
            }
        }
    }

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

// MARK: - Enrollment Preview Bar

private struct EnrollmentPreviewBar: View {
    let enrollments: [Enrollment]
    let avatars: [String: String]
    let isLoading: Bool
    var friendEmpNos: Set<String> = []

    private var previewStudents: [Enrollment] {
        Array(enrollments.filter { $0.primaryRole == .student }.prefix(5))
    }
    private var studentCount: Int { enrollments.filter { $0.primaryRole == .student }.count }
    private var friendCount: Int {
        enrollments.filter { $0.primaryRole == .student && friendEmpNos.contains($0.user.user_no) }.count
    }

    var body: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView().frame(width: 44, height: 32)
                Text("載入中...").font(.subheadline).foregroundStyle(.secondary)
            } else if enrollments.isEmpty {
                Image(systemName: "person.2").foregroundStyle(.secondary).frame(width: 44, height: 32)
                Text("查看修課名單").font(.subheadline).foregroundStyle(.secondary)
            } else {
                OverlappingAvatarStack(enrollments: previewStudents, avatars: avatars)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("\(studentCount) 名學生").font(.subheadline.weight(.medium))
                        if friendCount > 0 {
                            Text(" · \(friendCount) 位朋友")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    Text("點擊查看完整名單").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Overlapping Avatar Stack

private struct OverlappingAvatarStack: View {
    let enrollments: [Enrollment]
    let avatars: [String: String]

    private let size: CGFloat = 32
    private let overlap: CGFloat = 10

    var body: some View {
        HStack(spacing: -overlap) {
            ForEach(Array(enrollments.enumerated()), id: \.element.id) { index, enrollment in
                SmallAvatarView(
                    name: enrollment.user.name,
                    url: avatars["\(enrollment.user.id)"].flatMap { URL(string: $0) },
                    size: size
                )
                .zIndex(Double(enrollments.count - index))
            }
        }
    }
}

// MARK: - Small Avatar View

private struct SmallAvatarView: View {
    let name: String
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
            default:
                Circle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: size, height: size)
                    .overlay {
                        Text(String(name.prefix(1)))
                            .font(.system(size: size * 0.38, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
            }
        }
    }
}

// MARK: - Enrollment List View

struct EnrollmentListView: View {
    let enrollments: [Enrollment]
    let avatars: [String: String]
    let isLoading: Bool
    var friendEmpNos: Set<String> = []
    var publicProfilesByEmpNo: [String: PublicProfile] = [:]

    @State private var searchText = ""
    @State private var selectedMember: Enrollment? = nil

    private var filtered: [Enrollment] {
        guard !searchText.isEmpty else { return enrollments }
        let q = searchText.lowercased()
        return enrollments.filter {
            $0.user.name.lowercased().contains(q) ||
            $0.user.user_no.lowercased().contains(q) ||
            ($0.user.department?.name ?? "").lowercased().contains(q) ||
            ($0.user.klass?.name ?? "").lowercased().contains(q)
        }
    }

    private var instructors: [Enrollment] { filtered.filter { $0.primaryRole == .instructor } }
    private var tas: [Enrollment] { filtered.filter { $0.primaryRole == .ta } }
    private var allStudents: [Enrollment] { filtered.filter { $0.primaryRole == .student } }
    private var friendStudents: [Enrollment] { allStudents.filter { friendEmpNos.contains($0.user.user_no) } }
    private var otherStudents: [Enrollment] { allStudents.filter { !friendEmpNos.contains($0.user.user_no) } }

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if enrollments.isEmpty {
                ContentUnavailableView("無修課名單資料", systemImage: "person.2.slash")
            } else {
                if !instructors.isEmpty {
                    Section("教師") {
                        ForEach(instructors) { enrollmentRow($0) }
                    }
                }
                if !tas.isEmpty {
                    Section("助教") {
                        ForEach(tas) { enrollmentRow($0) }
                    }
                }
                // Friends section pinned to top of students
                if !friendStudents.isEmpty {
                    Section("你的朋友") {
                        ForEach(friendStudents) { enrollmentRow($0, isFriend: true) }
                    }
                }
                if !otherStudents.isEmpty {
                    Section("學生 (\(allStudents.count))") {
                        ForEach(otherStudents) { enrollmentRow($0) }
                    }
                }
                if filtered.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("修課名單")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "搜尋姓名、學號、系所")
        .sheet(item: $selectedMember) { member in
            EnrollmentMemberDetailView(
                enrollment: member,
                avatarURL: avatars["\(member.user.id)"] ?? publicProfilesByEmpNo[member.user.user_no]?.avatarURLString,
                publicProfile: publicProfilesByEmpNo[member.user.user_no]
            )
        }
    }

    @ViewBuilder
    private func enrollmentRow(_ enrollment: Enrollment, isFriend: Bool = false) -> some View {
        let isFriendMatch = isFriend || friendEmpNos.contains(enrollment.user.user_no)
        let hasPublicProfile = publicProfilesByEmpNo[enrollment.user.user_no] != nil
        Button {
            selectedMember = enrollment
        } label: {
            HStack(spacing: 12) {
                // Avatar with optional public-profile badge
                ZStack(alignment: .bottomTrailing) {
                    SmallAvatarView(
                        name: enrollment.user.name,
                        url: (avatars["\(enrollment.user.id)"] ?? publicProfilesByEmpNo[enrollment.user.user_no]?.avatarURLString)
                            .flatMap { URL(string: $0) },
                        size: 40
                    )
                    if hasPublicProfile {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white, .green)
                            .offset(x: 3, y: 3)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(enrollment.user.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        if enrollment.primaryRole != .student {
                            RoleBadge(role: enrollment.primaryRole)
                        }
                        if hasPublicProfile {
                            PublicProfileBadge()
                        }
                        if isFriendMatch {
                            FriendBadge()
                        }
                    }
                    HStack(spacing: 4) {
                        if !enrollment.user.user_no.isEmpty {
                            Text(enrollment.user.user_no).font(.caption).foregroundStyle(.secondary)
                        }
                        if let klass = enrollment.user.klass?.name {
                            Text("·").font(.caption).foregroundStyle(.tertiary)
                            Text(klass).font(.caption).foregroundStyle(.secondary)
                        } else if let dept = enrollment.user.department?.name {
                            Text("·").font(.caption).foregroundStyle(.tertiary)
                            Text(dept).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if enrollment.primaryRole == .student, let grade = enrollment.user.grade?.name {
                    Text(grade).font(.caption).foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Member Detail View

struct EnrollmentMemberDetailView: View {
    let enrollment: Enrollment
    let avatarURL: String?
    let publicProfile: PublicProfile?

    @Environment(\.dismiss) private var dismiss
    @State private var showAvatarMessage = false

    var body: some View {
        NavigationStack {
            List {
                // Avatar + name header
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            SmallAvatarView(
                                name: enrollment.user.name,
                                url: avatarURL.flatMap { URL(string: $0) },
                                size: 80
                            )
                            .onTapGesture { showAvatarMessage = true }
                            Text(enrollment.user.name)
                                .font(.title3.weight(.semibold))
                            HStack(spacing: 6) {
                                RoleBadge(role: enrollment.primaryRole)
                                if publicProfile != nil {
                                    PublicProfileBadge()
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if let publicProfile {
                    PublicProfileInfoSections(profile: publicProfile)
                }

                // Identity
                Section("基本資訊") {
                    if !enrollment.user.user_no.isEmpty {
                        LabeledContent("學號", value: enrollment.user.user_no)
                    }
                    if let nickname = enrollment.user.nickname, !nickname.isEmpty {
                        LabeledContent("暱稱", value: nickname)
                    }
                    LabeledContent("電子郵件", value: enrollment.user.email)
                }

                // Academic
                let hasDept = (enrollment.user.department?.name?.isEmpty == false)
                let hasKlass = (enrollment.user.klass?.name?.isEmpty == false)
                let hasGrade = (enrollment.user.grade?.name?.isEmpty == false)
                let hasOrg = (enrollment.user.org?.name?.isEmpty == false)

                if hasDept || hasKlass || hasGrade || hasOrg {
                    Section("學籍資訊") {
                        if let org = enrollment.user.org?.name, !org.isEmpty {
                            LabeledContent("學校", value: org)
                        }
                        if let dept = enrollment.user.department?.name, !dept.isEmpty {
                            LabeledContent("系所", value: dept)
                        }
                        if let klass = enrollment.user.klass?.name, !klass.isEmpty {
                            LabeledContent("班級", value: klass)
                        }
                        if let grade = enrollment.user.grade?.name, !grade.isEmpty {
                            LabeledContent("年級", value: grade)
                        }
                    }
                }

                // Course role
                Section("課程身份") {
                    LabeledContent("身份", value: enrollment.primaryRole.displayName)
                    if !enrollment.seat_number.isEmpty {
                        LabeledContent("座位號碼", value: enrollment.seat_number)
                    }
                    if enrollment.retake_status {
                        LabeledContent("重修", value: "是")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("成員資訊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Role Badge

private struct RoleBadge: View {
    let role: EnrollmentRole

    var body: some View {
        Text(role.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(role == .instructor ? Color.blue : Color.orange, in: Capsule())
    }
}

private struct PublicProfileBadge: View {
    var body: some View {
        Label("公開", systemImage: "checkmark.seal.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.green)
            .labelStyle(.iconOnly)
            .accessibilityLabel("已啟用公開資料")
    }
}

private struct FriendBadge: View {
    var body: some View {
        Text("朋友")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppTheme.accent.opacity(0.12), in: Capsule())
    }
}


// MARK: - Detail Text Row

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
