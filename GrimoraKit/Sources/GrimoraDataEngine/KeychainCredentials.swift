import Foundation
import Security

struct TigrisCredentials: Sendable {
  var accessKeyID: String
  var secretAccessKey: String
}

enum KeychainCredentials {
  static let service = "com.samwagner.GrimoraDataEngine.tigris"

  static func load(environment: [String: String]) throws -> TigrisCredentials {
    if let accessKey = environment["TIGRIS_ACCESS_KEY_ID"] ?? environment["AWS_ACCESS_KEY_ID"],
      let secretKey = environment["TIGRIS_SECRET_ACCESS_KEY"] ?? environment["AWS_SECRET_ACCESS_KEY"]
    {
      return TigrisCredentials(accessKeyID: accessKey, secretAccessKey: secretKey)
    }
    guard let accessKey = read(account: "access-key-id"),
      let secretKey = read(account: "secret-access-key")
    else {
      throw EngineError.missingTigrisCredentials
    }
    return TigrisCredentials(accessKeyID: accessKey, secretAccessKey: secretKey)
  }

  private static func read(account: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }
}
