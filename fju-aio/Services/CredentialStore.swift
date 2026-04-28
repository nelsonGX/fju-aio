import Foundation

nonisolated struct LDAPCredentials: Codable, Sendable {
    let username: String
    let password: String
}

final class CredentialStore: Sendable {
    nonisolated static let shared = CredentialStore()
    
    private let keychain = KeychainManager.shared
    private let credentialsKey = "com.fju.ldap.credentials"
    
    private init() {}
    
    // MARK: - LDAP Credentials
    
    nonisolated func saveLDAPCredentials(username: String, password: String) throws {
        let credentials = LDAPCredentials(username: username, password: password)
        let data = try JSONEncoder().encode(credentials)
        try keychain.save(data, for: credentialsKey)
    }
    
    nonisolated func retrieveLDAPCredentials() throws -> LDAPCredentials {
        let data = try keychain.retrieve(for: credentialsKey)
        return try JSONDecoder().decode(LDAPCredentials.self, from: data)
    }
    
    nonisolated func deleteLDAPCredentials() throws {
        try keychain.delete(for: credentialsKey)
    }
    
    nonisolated func hasLDAPCredentials() -> Bool {
        do {
            _ = try retrieveLDAPCredentials()
            return true
        } catch {
            return false
        }
    }
}
