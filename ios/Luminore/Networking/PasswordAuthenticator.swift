import CryptoKit
import Foundation
import LuminoreCore

enum PasswordAuthenticator {
    static func challenge() -> AuthChallenge {
        AuthChallenge(salt: randomData(count: 16), nonce: randomData(count: 32))
    }

    static func code(password: String, challenge: AuthChallenge) -> Data {
        var material = Data(password.precomposedStringWithCanonicalMapping.utf8)
        material.append(challenge.salt)
        let key = SymmetricKey(data: SHA256.hash(data: material))
        return Data(HMAC<SHA256>.authenticationCode(for: challenge.nonce, using: key))
    }

    static func verify(_ code: Data, password: String, challenge: AuthChallenge) -> Bool {
        let expected = self.code(password: password, challenge: challenge)
        return code.count == expected.count && zip(code, expected).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func randomData(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0 ..< count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}
