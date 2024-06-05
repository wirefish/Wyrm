import XCTest
@testable import Wyrm

final class NounPhraseTests: XCTestCase {
  static let examples = [
    ("a rock", "a", "rock", "rocks"),
    ("the fox", "the", "fox", "foxes"),
    ("apple", "an", "apple", "apples"),
    ("box[es] of dirt", "a", "box of dirt", "boxes of dirt"),
    ("sarcophag[us|i]", "a", "sarcophagus", "sarcophagi"),
    ("t[oo|ee]th", "a", "tooth", "teeth"),
    ("Bob", nil, "Bob", "Bob")
  ]

  func testInit() throws {
    for (phrase, article, singular, plural) in Self.examples {
      let noun = NounPhrase(phrase)
      XCTAssertEqual(noun.article, article)
      XCTAssertEqual(noun.singular, singular)
      XCTAssertEqual(noun.plural, plural)
    }
  }
}
