//
//  Database.swift
//  Wyrm
//

import Foundation

struct DatabaseError: Error, CustomStringConvertible {
  let description: String

  init(_ description: String) {
    self.description = description
  }
}

typealias AccountID = Int64

class Database {
  private var conn: SQLiteConnection!
  private var createAccountStmt: SQLiteStatement!
  private var createAvatarStmt: SQLiteStatement!
  private var getCredentialsStmt: SQLiteStatement!
  private var loadAvatarStmt: SQLiteStatement!
  private var saveAvatarStmt: SQLiteStatement!
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

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
        logger.warning("no avatar found for accountID \(accountID)")
        return nil
      }
      let encodedAvatar = row.getBlob(0)
      let avatar = try decoder.decode(Avatar.self, from: Data(encodedAvatar!))
      avatar.accountID = accountID
      return avatar
    } catch {
      logger.error("error loading avatar for account \(accountID): \(error)")
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

  private func encodeAvatar(_ avatar: Avatar) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
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
