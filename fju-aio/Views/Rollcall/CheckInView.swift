import SwiftUI

struct CheckInView: View {
    @State private var rollcalls: [Rollcall] = []
    @State private var isLoading = false
    @State private var checkInResults: [Int: RollcallCheckInResult] = [:]
    @State private var showManualEntry = false
    @State private var selectedRollcall: Rollcall? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        List {
            if !isLoading && rollcalls.isEmpty {
                ContentUnavailableView(
                    "目前沒有點名",
                    systemImage: "hand.raised.slash",
                    description: Text("向下滑動以重新整理")
                )
                .listRowBackground(Color.clear)
            }

            ForEach(rollcalls) { rollcall in
                RollcallRowView(
                    rollcall: rollcall,
                    result: checkInResults[rollcall.rollcall_id],
                    onManualEntry: {
                        selectedRollcall = rollcall
                        showManualEntry = true
                    }
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
        }
        .navigationTitle("課程簽到")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading { ProgressView() }
        }
        .task { await loadRollcalls() }
        .refreshable { await loadRollcalls() }
        .alert("錯誤", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("確定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showManualEntry) {
            if let rollcall = selectedRollcall {
                ManualCheckInSheet(rollcall: rollcall) { code in
                    showManualEntry = false
                    Task { await doManualCheckIn(rollcall: rollcall, code: code) }
                }
            }
        }
    }

    private func loadRollcalls() async {
        isLoading = true
        defer { isLoading = false }
        do {
            rollcalls = try await RollcallService.shared.fetchActiveRollcalls()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func doManualCheckIn(rollcall: Rollcall, code: String) async {
        do {
            let success = try await RollcallService.shared.manualCheckIn(rollcall: rollcall, code: code)
            checkInResults[rollcall.rollcall_id] = success ? .success(code) : .failure("數字碼錯誤，請再試一次")
        } catch {
            checkInResults[rollcall.rollcall_id] = .failure(error.localizedDescription)
        }
    }
}

// MARK: - Rollcall Row

private struct RollcallRowView: View {
    let rollcall: Rollcall
    let result: RollcallCheckInResult?
    let onManualEntry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rollcall.course_title)
                        .font(.headline)
                    Text(rollcall.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(rollcall.created_by_name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(rollcall: rollcall)
            }

            HStack(spacing: 6) {
                Image(systemName: rollcall.is_number ? "number.circle.fill" : "location.circle.fill")
                    .font(.caption)
                Text(rollcall.is_number ? "數字碼點名" : "雷達點名")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            if rollcall.isActive && !rollcall.isAlreadyCheckedIn {
                if let result {
                    resultView(result)
                } else if rollcall.is_number {
                    Button(action: onManualEntry) {
                        Label("輸入數字碼", systemImage: "keyboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                } else {
                    Text("雷達點名目前不支援")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func resultView(_ result: RollcallCheckInResult) -> some View {
        switch result {
        case .success(let code):
            Label("簽到成功！數字碼：\(code)", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let rollcall: Rollcall

    private var label: (text: String, color: Color) {
        switch rollcall.status {
        case "on_call": return ("已簽到", .green)
        case "late":    return ("遲到",   .orange)
        default:
            if rollcall.is_expired { return ("已過期", .gray) }
            if rollcall.rollcall_status == "in_progress" { return ("進行中", .blue) }
            return ("缺席", .red)
        }
    }

    var body: some View {
        Text(label.text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(label.color.opacity(0.15))
            .foregroundStyle(label.color)
            .clipShape(Capsule())
    }
}

// MARK: - Manual Entry Sheet

struct ManualCheckInSheet: View {
    let rollcall: Rollcall
    let onConfirm: (String) -> Void

    @State private var code = ""
    @Environment(\.dismiss) private var dismiss

    private var paddedCode: String {
        String(repeating: "0", count: max(0, 4 - code.count)) + code
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                VStack(spacing: 6) {
                    Text(rollcall.course_title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("請向教師確認點名數字碼")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                TextField("0000", text: $code)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .onChange(of: code) { _, new in
                        code = String(new.filter(\.isNumber).prefix(4))
                    }
                    .padding()
                    .frame(maxWidth: 200)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Button {
                    onConfirm(paddedCode)
                } label: {
                    Text("確認簽到")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .disabled(code.count != 4)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 32)
            .navigationTitle("手動輸入數字碼")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CheckInView()
    }
}
