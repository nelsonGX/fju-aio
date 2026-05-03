import SwiftUI

// EmergencyContact, DepartmentContact and data arrays are defined in ContactData.swift

// MARK: - View

struct ContactInfoView: View {
    @State private var searchText = ""

    private var filteredEmergency: [EmergencyContact] {
        guard !searchText.isEmpty else { return allEmergencyContacts }
        return allEmergencyContacts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.phone.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredDepartments: [DepartmentContact] {
        guard !searchText.isEmpty else { return allDepartmentContacts }
        return allDepartmentContacts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.email?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            $0.phones.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        List {
            if searchText.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("天主教輔仁大學")
                            .font(.headline)
                        Text("242062 新北市新莊區中正路 510 號")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ContactPhoneLink(phone: "(02) 2905-2000")
                    }
                    .padding(.vertical, 4)
                }
            }

            if !filteredEmergency.isEmpty {
                Section("緊急聯絡") {
                    ForEach(filteredEmergency) { contact in
                        ContactRow(name: contact.name, phone: contact.phone)
                    }
                }
            }

            if !filteredDepartments.isEmpty {
                Section("業務單位") {
                    ForEach(filteredDepartments) { dept in
                        DepartmentRow(contact: dept)
                    }
                }
            }
        }
        .navigationTitle("常用聯絡資訊")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜尋單位、業務、電話或 Email")
    }
}

// MARK: - Subviews

private struct ContactRow: View {
    let name: String
    let phone: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                ContactPhoneLink(phone: phone)
            }
            Spacer()
            Image(systemName: "phone.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }
}

private struct DepartmentRow: View {
    let contact: DepartmentContact

    private var primaryPhone: URL? {
        guard let first = contact.phones.first else { return nil }
        let base = first.components(separatedBy: " (").first ?? first
        let digits = base.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    private var mailURL: URL? {
        guard let email = contact.email else { return nil }
        return URL(string: "mailto:\(email)")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                if let first = contact.phones.first {
                    Text(first)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                if let url = primaryPhone {
                    Link(destination: url) {
                        Image(systemName: "phone.fill")
                            .font(.subheadline)
                            .frame(width: 36, height: 36)
                            .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.green)
                    }
                }
                if let url = mailURL {
                    Link(destination: url) {
                        Image(systemName: "envelope.fill")
                            .font(.subheadline)
                            .frame(width: 36, height: 36)
                            .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct ContactPhoneLink: View {
    let phone: String

    /// Returns a tel:-dialable number by stripping parenthetical labels like "(總機)"
    private var callURL: URL? {
        let base = phone.components(separatedBy: " (").first ?? phone
        let digits = base.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    var body: some View {
        if let url = callURL {
            Link(phone, destination: url)
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Text(phone)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}


#Preview {
    NavigationStack {
        ContactInfoView()
    }
}
