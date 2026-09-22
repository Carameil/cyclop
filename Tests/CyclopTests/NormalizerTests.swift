import Foundation
import Testing
@testable import Cyclop

/// Тесты на `Normalizer` — чистые преобразования вкладки «Инструменты».
/// Панель сюда не входит, как и везде: см. CONTRIBUTING.md.
struct NormalizerTests {

    // MARK: - Что распознаётся

    @Test func emptyInputIsEmpty() {
        #expect(Normalizer.normalize("   \n ") == .empty)
    }

    @Test func idsSeparatedByNewlinesBecomeCommaSeparated() {
        let result = Normalizer.normalize("101\n102\n103")
        #expect(result.kind == .ids)
        #expect(result.output == "101, 102, 103")
    }

    @Test func idsSeparatedBySpacesTabsCommasAndSemicolonsAreOneList() {
        let result = Normalizer.normalize("1 2\t3,4;5\n\n6,,7")
        #expect(result.output == "1, 2, 3, 4, 5, 6, 7")
    }

    @Test func nonNumericTokensStillJoin() {
        let result = Normalizer.normalize("abc-1\nabc-2")
        #expect(result.kind == .ids)
        #expect(result.output == "abc-1, abc-2")
    }

    /// Одно число из десяти цифр — момент, а не id. Из девяти или одиннадцати
    /// — id: тогда `date(fromTimestamp:)` отвечает nil и текст идёт в список.
    @Test func lonelyIdOfOtherLengthStaysAnId() {
        #expect(Normalizer.normalize("123456789").kind == .ids)
        #expect(Normalizer.normalize("12345678901").kind == .ids)
    }

    // MARK: - JSON

    @Test func minifiedJSONIsIndentedWithKeysInOriginalOrder() throws {
        let result = Normalizer.normalize(#"{"z":1,"a":{"y":[1,2],"b":"x"}}"#)
        #expect(result.kind == .json)
        #expect(result.output == """
        {
          "z": 1,
          "a": {
            "y": [
              1,
              2
            ],
            "b": "x"
          }
        }
        """)
    }

    @Test func emptyContainersStayOnOneLine() throws {
        let output = try Normalizer.prettyJSON(#"{"a":{},"b":[ ]}"#)
        #expect(output == """
        {
          "a": {},
          "b": []
        }
        """)
    }

    /// Скобки и запятые внутри строк — текст, а не структура.
    @Test func bracesInsideStringsAreLeftAlone() throws {
        let output = try Normalizer.prettyJSON(#"{"s":"a{b,c}\"d\\","n":null}"#)
        #expect(output == """
        {
          "s": "a{b,c}\\"d\\\\",
          "n": null
        }
        """)
    }

    @Test func alreadyPrettyJSONIsNormalised() throws {
        let pretty = try Normalizer.prettyJSON("{\n    \"a\" :  1 ,\n\n \"b\":[true]}")
        #expect(pretty == """
        {
          "a": 1,
          "b": [
            true
          ]
        }
        """)
    }

    /// Пропущенная запятая, а не лишняя: `{"a":1,}` Foundation на macOS 15
    /// принимает, так что висящая запятая — не пример невалидного JSON.
    @Test func invalidJSONIsReportedNotSwallowed() {
        let result = Normalizer.normalize(#"{"a":1 "b":2}"#)
        #expect(result.kind == .invalid)
        #expect(result.output.isEmpty)
        #expect(result.failure?.isEmpty == false)
    }

    // MARK: - Время

    @Test func unixSecondsBecomeADateInUTCAndLocal() {
        let result = Normalizer.normalize("1700000000")
        #expect(result.kind == .timestamp)
        #expect(result.output.hasPrefix("2023-11-14 22:13:20 UTC\n"))
        #expect(result.output.split(separator: "\n").count == 2)
    }

    @Test func unixMillisecondsAreRecognisedByLength() {
        let result = Normalizer.normalize("1700000000123")
        #expect(result.kind == .timestamp)
        #expect(result.output.hasPrefix("2023-11-14 22:13:20 UTC"))
    }

    @Test func isoDateBecomesUnixSeconds() {
        #expect(Normalizer.normalize("2023-11-14T22:13:20Z").output == "1700000000")
        #expect(Normalizer.normalize("2023-11-14 22:13:20").output == "1700000000")
        #expect(Normalizer.normalize("2023-11-14").output == "1699920000")
        #expect(Normalizer.normalize("2023-11-14").kind == .date)
    }

    @Test func dateWithOffsetIsConvertedThroughIt() {
        #expect(Normalizer.normalize("2023-11-15T01:13:20+03:00").output == "1700000000")
    }
}
