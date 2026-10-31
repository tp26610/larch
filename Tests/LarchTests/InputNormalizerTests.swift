import Foundation
import Testing
@testable import Larch

struct InputNormalizerTests {
    @Test func emptyIsNil() {
        #expect(InputNormalizer.normalize("") == nil)
        #expect(InputNormalizer.normalize("  \n ") == nil)
    }

    @Test func fullHTTPURLKeptAsIs() {
        let r = InputNormalizer.normalize("https://example.com/a?b=1")
        #expect(r?.kind == .url)
        #expect(r?.url.absoluteString == "https://example.com/a?b=1")
    }

    @Test func disallowedSchemesRejected() {
        #expect(InputNormalizer.normalize("file:///etc/passwd") == nil)
        #expect(InputNormalizer.normalize("javascript://alert(1)") == nil)
        #expect(InputNormalizer.normalize("mailto://a@b.com") == nil)
    }

    @Test func bareHostGetsHTTPS() {
        let r = InputNormalizer.normalize("example.com/path")
        #expect(r?.kind == .url)
        #expect(r?.url.absoluteString == "https://example.com/path")
    }

    @Test func localhostAndIPGetHTTP() {
        #expect(InputNormalizer.normalize("localhost:3000")?.url.absoluteString == "http://localhost:3000")
        #expect(InputNormalizer.normalize("192.168.1.1/admin")?.url.absoluteString == "http://192.168.1.1/admin")
    }

    @Test func plainWordsBecomeSearch() {
        let r = InputNormalizer.normalize("swift testing")
        #expect(r?.kind == .search)
        #expect(r?.url.absoluteString == InputNormalizer.searchPrefix + "swift%20testing")
    }

    @Test func singleWordWithoutDotIsSearch() {
        #expect(InputNormalizer.normalize("github")?.kind == .search)
    }

    @Test func hostWithSpaceIsSearch() {
        #expect(InputNormalizer.normalize("example.com foo")?.kind == .search)
    }

    @Test func searchPercentEncodesSpecialCharacters() {
        let r = InputNormalizer.normalize("a&b=c")
        #expect(r?.kind == .search)
        #expect(r?.url.absoluteString == InputNormalizer.searchPrefix + "a%26b%3Dc")
    }

    @Test func nonASCIIQueryIsEncodedSearch() {
        let r = InputNormalizer.normalize("固定支出")
        #expect(r?.kind == .search)
        #expect(r?.url.absoluteString.hasPrefix(InputNormalizer.searchPrefix) == true)
    }

    @Test func trimsWhitespace() {
        #expect(InputNormalizer.normalize("  example.com  ")?.url.absoluteString == "https://example.com")
    }

    @Test func isHTTP() {
        #expect(InputNormalizer.isHTTP(URL(string: "https://a.com")))
        #expect(InputNormalizer.isHTTP(URL(string: "HTTP://a.com")))
        #expect(!InputNormalizer.isHTTP(URL(string: "file:///a")))
        #expect(!InputNormalizer.isHTTP(URL(string: "about:blank")))
        #expect(!InputNormalizer.isHTTP(nil))
    }
}
