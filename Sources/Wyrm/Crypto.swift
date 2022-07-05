//
//  Crypto.swift
//  Wyrm
//

import Foundation
import CommonCrypto
import Security

func getRandomBytes(_ count: Int) -> [UInt8]? {
    var bytes = [UInt8](repeating: 0, count: count)
    return bytes.withUnsafeMutableBytes({
        SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
    }) == errSecSuccess ? bytes : nil
}

func derivePasswordKey(_ password: String, _ salt: [UInt8]) -> [UInt8]? {
    let passwordData = password.data(using: .utf8)!
    var derivedKey = [UInt8](repeating: 0, count: 32)
    let success = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
        salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                password, passwordData.count,
                saltBytes.baseAddress, saltBytes.count,
                CCPBKDFAlgorithm(kCCPRFHmacAlgSHA1),
                UInt32(1 << 12),
                derivedKeyBytes.baseAddress, derivedKeyBytes.count) == kCCSuccess
        }
    }
    return success ? derivedKey : nil
}

func computeDigest(_ data: Data) -> Data {
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { let _ = CC_SHA256($0.baseAddress!, CC_LONG($0.count), &digest) }
    return Data(digest)
}
