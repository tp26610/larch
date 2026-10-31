import Testing
@testable import Larch

struct FuzzyTests {
    @Test func emptyTermScoresZero() {
        #expect(Fuzzy.score(term: "", in: "anything") == 0)
        #expect(Fuzzy.score(query: "   ", in: "anything") == 0)
    }

    @Test func emptyTextNeverMatches() {
        #expect(Fuzzy.score(term: "a", in: "") == -1)
    }

    @Test func substringMatchIsCaseInsensitive() {
        #expect(Fuzzy.score(term: "GITHUB", in: "github.com") > 0)
    }

    @Test func prefixBeatsMidWordMatch() {
        #expect(Fuzzy.score(term: "git", in: "GitHub") > Fuzzy.score(term: "git", in: "Digital"))
    }

    @Test func wordBoundaryBeatsMidWord() {
        #expect(Fuzzy.score(term: "hub", in: "git hub") > Fuzzy.score(term: "hub", in: "githubx"))
    }

    @Test func subsequenceFallback() {
        #expect(Fuzzy.score(term: "gh", in: "GitHub") > 0)
    }

    @Test func singleCharacterDoesNotUseSubsequence() {
        #expect(Fuzzy.score(term: "z", in: "abc") == -1)
    }

    @Test func subsequenceDisabledForLongText() {
        let long = String(repeating: "a-", count: 40) + "xyz"
        #expect(Fuzzy.score(term: "ayz", in: long) == -1)
    }

    @Test func allTermsMustMatch() {
        #expect(Fuzzy.score(query: "git hub", in: "GitHub repo") > 0)
        #expect(Fuzzy.score(query: "git nope", in: "GitHub repo") == -1)
    }

    @Test func queryScoreSumsTerms() {
        let one = Fuzzy.score(term: "git", in: "git hub")
        let two = Fuzzy.score(term: "hub", in: "git hub")
        #expect(Fuzzy.score(query: "git hub", in: "git hub") == one + two)
    }
}
