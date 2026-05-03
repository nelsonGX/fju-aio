import SwiftUI

struct LoginView: View {
    @Environment(AuthenticationManager.self) private var authManager
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.top, 64)
                            .padding(.bottom, 8)

                        Text("輔大 All In One")
                            .font(.title.bold())

                        Text("使用 LDAP 統一帳號密碼登入")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 48)

                    // Form
                    VStack(spacing: 12) {
                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                TextField("學號", text: $username)
                                    .textContentType(.username)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .submitLabel(.next)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Divider()
                                .padding(.leading, 52)

                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                SecureField("密碼", text: $password)
                                    .textContentType(.password)
                                    .submitLabel(.go)
                                    .onSubmit {
                                        guard !username.isEmpty && !password.isEmpty else { return }
                                        Task { await performLogin() }
                                    }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

                        if let errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                        }

                        // Login button
                        Button {
                            Task { await performLogin() }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                    .fill(isButtonDisabled ? AppTheme.accent.opacity(0.35) : AppTheme.accent)

                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("登入")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                        }
                        .buttonStyle(.plain)
                        .disabled(isButtonDisabled)
                        .animation(.easeInOut(duration: 0.15), value: isButtonDisabled)
                        
                        Link(destination: URL(string: "https://whoami.fju.edu.tw/info_ac.php")!) {
                            HStack(spacing: 4) {
                                Text("輔大新人還沒有帳號？")
                                    .foregroundStyle(.secondary)
                                Text("跟學校拿個帳號")
                                    .fontWeight(.semibold)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                            }
                            .font(.footnote)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                        }
                        
                        Link(destination: URL(string: "http://smis.fju.edu.tw/DepartNew/Query.aspx")!) {
                            HStack(spacing: 4) {
                                Text("蛤？不知道學號？")
                                    .fontWeight(.semibold)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                            }
                            .font(.footnote)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                        }

                        Text("不是輔大的但想進去看看？用帳密 \"demo\" 登入")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                        .tint(AppTheme.accent)
                    }
                    .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var isButtonDisabled: Bool {
        isLoading || username.isEmpty || password.isEmpty
    }

    private func performLogin() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await authManager.login(username: username, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthenticationManager())
}
