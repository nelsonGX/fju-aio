import SwiftUI

struct LoginView: View {
    @Environment(AuthenticationManager.self) private var authManager
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Logo
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)
                    .padding(.bottom, 20)
                
                Text("輔大校務系統")
                    .font(.title.bold())
                
                // Login Form
                VStack(spacing: 16) {
                    TextField("學號", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    
                    SecureField("密碼", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Button {
                        Task {
                            await performLogin()
                        }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("登入")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(isLoading || username.isEmpty || password.isEmpty)
                }
                .padding(.horizontal)
                
                Spacer()
                
                Text("使用 LDAP 統一帳號密碼登入")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("登入")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func performLogin() async {
        errorMessage = nil
        
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
