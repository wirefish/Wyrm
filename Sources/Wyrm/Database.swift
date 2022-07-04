//
//  Database.swift
//  Wyrm
//

import CommonCrypto
import Security

struct DatabaseError: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}

class Database {
    typealias AccountID = Int64

    private var conn: SQLiteConnection!
    private var createAccountStmt: SQLiteStatement!
    private var createAvatarStmt: SQLiteStatement!
    private var getCredentialsStmt: SQLiteStatement!
    private var loadAvatarStmt: SQLiteStatement!
    private var saveAvatarStmt: SQLiteStatement!

    func open(_ path: String) -> Result<Void, DatabaseError> {
        do {
            conn = try SQLiteConnection(path)
            createAccountStmt = try SQLiteStatement(conn, Self.createAccountSQL)
            createAvatarStmt = try SQLiteStatement(conn, Self.createAvatarSQL)
            getCredentialsStmt = try SQLiteStatement(conn, Self.getCredentialsSQL)
            loadAvatarStmt = try SQLiteStatement(conn, Self.loadAvatarSQL)
            saveAvatarStmt = try SQLiteStatement(conn, Self.saveAvatarSQL)
           return .success(())
        } catch let error as SQLiteError {
            return .failure(DatabaseError(message: error.message))
        } catch {
            return .failure(DatabaseError(message: "unexpected error: \(error)"))
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

    func createAccount(username: String, password: String, avatar: Avatar)
    -> Result<AccountID, DatabaseError> {
        if let error = validateUsername(username) ?? validatePassword(password) {
            return .failure(error)
        }
        guard let salt = randomBytes(16) else {
            return .failure(DatabaseError(message: "cannot create password salt"))
        }
        guard let passwordKey = derivePasswordKey(password, salt) else {
            return .failure(DatabaseError(message: "cannot derive password key"))
        }

        // TODO: serialize avatar
        let avatarData = "avatar"
        let location = "location"

        do {
            return .success(try conn.inTransaction { () -> AccountID in
                try createAccountStmt.execute(username, passwordKey, salt)
                let accountID = conn.lastInsertedRowID
                try createAvatarStmt.execute(accountID, location, avatarData)
                return accountID
            })
        } catch let e as SQLiteError {
            return .failure(DatabaseError(message: e.message))
        } catch {
            return .failure(DatabaseError(message: "unexpected error: \(error)"))
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
                logger.error("internal error getting authentication data")
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
            let location = row.getString(0)
            let avatarData = row.getString(1)
            return nil
        } catch {
            return nil
        }
    }

    private func validateUsername(_ username: String) -> DatabaseError? {
        if username.count < 3 {
            return DatabaseError(message: "username must be at least 3 characters long")
        } else if username.count > 20 {
            return DatabaseError(message: "username must be no more than 20 characters long")
        } else if !username.allSatisfy({ $0.isLetter || $0.isWholeNumber || $0 == "_" }) {
            return DatabaseError(message: "username must contain only letters or numbers")
        }
        return nil
    }

    private func validatePassword(_ password: String) -> DatabaseError? {
        if password.count < 8 {
            return DatabaseError(message: "password must be at least 8 characters long")
        } else if password.count > 40 {
            return DatabaseError(message: "password must be no more than 40 characters long")
        } else if !password.allSatisfy({
            $0.isLetter || $0.isPunctuation || $0.isWholeNumber ||
            ($0.isWhitespace && !$0.isNewline) }) {
            return DatabaseError(
                message: "password must contain only letters, punctuation, numbers, or whitespace")
        }
        return nil
    }

    private func randomBytes(_ count: Int) -> [UInt8]? {
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

    private static let createAccountSQL = """
    insert into accounts (username, password_key, salt) values (?, ?, ?)
    """

    private static let createAvatarSQL = """
    insert into avatars (account_id, location, avatar) values (?, ?, ?)
    """

    private static let getCredentialsSQL = """
    select account_id, password_key, salt from accounts where username = ?
    """

    private static let setPasswordSQL = """
    update accounts set password_key = ?, salt = ? where account_id = ?
    """

    private static let loadAvatarSQL = """
    select location, avatar from avatars where account_id = ?
    """

    private static let saveAvatarSQL = """
       update avatars set location = ?, avatar = ? where account_id = ?
    """
}
