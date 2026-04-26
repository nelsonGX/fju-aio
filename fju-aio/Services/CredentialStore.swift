import Foundation

struct LDAPCredentials: Codable, Sendable {
    let username: String
    let password: String
}

final class CredentialStore: Sendable {
    static let shared = CredentialStore()
    
    private let keychain = KeychainManager.shared
    private let credentialsKey = "com.fju.ldap.credentials"
    
    private init() {}
    
    // MARK: - LDAP Credentials
    
    func saveLDAPCredentials(username: String, password: String) throws {
        let credentials = LDAPCredentials(username: username, password: password)
        let data = try JSONEncoder().encode(credentials)
        try keychain.save(data, for: credentialsKey)
    }
    
    func retrieveLDAPCredentials() throws -> LDAPCredentials {
        let data = try keychain.retrieve(for: credentialsKey)
        return try JSONDecoder().decode(LDAPCredentials.self, from: data)
    }
    
    func deleteLDAPCredentials() throws {
        try keychain.delete(for: credentialsKey)
    }
    
    func hasLDAPCredentials() -> Bool {
        do {
            _ = try retrieveLDAPCredentials()
            return true
        } catch {
            return false
        }
    }
}
