//
//  Database.swift
//  Wyrm
//

import Foundation
import CommonCrypto
import Security

struct DatabaseError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

class Database {
    typealias AccountID = Int64

    private var conn: SQLiteConnection!
    private var createAccountStmt: SQLiteStatement!
    private var createAvatarStmt: SQLiteStatement!
    private var getCredentialsStmt: SQLiteStatement!
    private var loadAvatarStmt: SQLiteStatement!
    private var saveAvatarStmt: SQLiteStatement!

    // MARK: - public methods

    func open(_ path: String) -> Bool {
        do {
            conn = try SQLiteConnection(path)
            createAccountStmt = try SQLiteStatement(conn, Self.createAccountSQL)
            createAvatarStmt = try SQLiteStatement(conn, Self.createAvatarSQL)
            getCredentialsStmt = try SQLiteStatement(conn, Self.getCredentialsSQL)
            loadAvatarStmt = try SQLiteStatement(conn, Self.loadAvatarSQL)
            saveAvatarStmt = try SQLiteStatement(conn, Self.saveAvatarSQL)
            return true
        } catch {
            logger.error("cannot open database at \(path): \(error)")
            return false
        }
    }

    func close() {
        createAccountStmt?.finalize()
        createAvatarStmt?.finalize()
        getCredentialsStmt?.finalize()
        loadAvatarStmt?.finalize()
        saveAvatarStmt?.finalize()
        conn?.close()
    }

    func createAccount(username: String, password: String, avatar: Avatar) -> AccountID? {
        guard validateUsername(username) && validatePassword(password) else {
            return nil
        }

        guard let salt = getRandomBytes(16),
              let passwordKey = derivePasswordKey(password, salt) else {
            return nil
        }

        do {
            return try conn.inTransaction { () -> AccountID in
                try createAccountStmt.execute(username, passwordKey, salt)
                let accountID = conn.lastInsertedRowID
                try createAvatarStmt.execute(accountID, encodeAvatar(avatar))
                return accountID
            }
        } catch {
            logger.error("cannot create account for user \(username): \(error)")
            return nil
        }
    }

    func authenticate(username: String, password: String) -> AccountID? {
        do {
            var results = try getCredentialsStmt.query(username)
            guard let row = results.next() else {
                return nil
            }
            guard let accountID = row.getInt64(0),
                  let passwordKey = row.getBlob(1),
                  let salt = row.getBlob(2) else {
                logger.error("cannot get authentication data for user \(username)")
                return nil
            }
            return derivePasswordKey(password, salt) == passwordKey ? accountID : nil
        } catch {
            logger.error("error authenticating user \(username): \(error)")
            return nil
        }
    }

    func loadAvatar(accountID: AccountID) -> Avatar? {
        do {
            var results = try loadAvatarStmt.query(accountID)
            guard let row = results.next() else {
                return nil
            }
            let encodedAvatar = row.getString(0)
            return nil
        } catch {
            return nil
        }
    }

    func saveAvatar(accountID: AccountID, avatar: Avatar) -> Bool {
        do {
            try saveAvatarStmt.execute(encodeAvatar(avatar), accountID)
            return true
        } catch {
            logger.error("error saving avatar for account \(accountID): \(error)")
            return false
        }
    }

    // MARK: - private methods

    private func validateUsername(_ username: String) -> Bool {
        return (username.count >= 3 &&
                username.count <= 20 &&
                username.allSatisfy { $0.isLetter || $0.isWholeNumber || $0 == "_" })
    }

    private func validatePassword(_ password: String) -> Bool {
        return (password.count >= 8 &&
                password.count <= 40 &&
                password.allSatisfy {
                    $0.isLetter || $0.isPunctuation || $0.isWholeNumber ||
                    ($0.isWhitespace && !$0.isNewline)
                })
    }

    private func getRandomBytes(_ count: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: count)
        return bytes.withUnsafeMutableBytes({
            SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
        }) == errSecSuccess ? bytes : nil
    }

    private func derivePasswordKey(_ password: String, _ salt: [UInt8]) -> [UInt8]? {
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

    private func encodeAvatar(_ avatar: Avatar) -> String {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(avatar)
        return String(data: data, encoding: .utf8)!
    }

    private static let createAccountSQL = """
    insert into accounts (username, password_key, salt) values (?, ?, ?)
    """

    private static let createAvatarSQL = """
    insert into avatars (account_id, avatar) values (?, ?)
    """

    private static let getCredentialsSQL = """
    select account_id, password_key, salt from accounts where username = ?
    """

    private static let setPasswordSQL = """
    update accounts set password_key = ?, salt = ? where account_id = ?
    """

    private static let loadAvatarSQL = """
    select avatar from avatars where account_id = ?
    """

    private static let saveAvatarSQL = """
       update avatars set avatar = ? where account_id = ?
    """
}
