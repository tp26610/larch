import Foundation

/// 模糊比對（對應 my-browser util.js 的 fuzzy / scoreTerms）。分數越高越好，-1 表示不符。
enum Fuzzy {
    private static let subsequenceMaxLength = 60

    private static func isBoundary(_ t: [Character], _ i: Int) -> Bool {
        if i == 0 { return true }
        let p = t[i - 1]
        return p.isWhitespace || "-_/.:".contains(p)
    }

    static func score(term: String, in text: String) -> Int {
        let q = Array(term.lowercased())
        let t = Array(text.lowercased())
        if q.isEmpty { return 0 }
        if t.isEmpty { return -1 }

        if let idx = indexOf(q, in: t, from: 0) {
            return 100 - min(idx, 60) + (idx == 0 ? 40 : 0) + (isBoundary(t, idx) ? 20 : 0)
        }
        // 子序列備援（"gh" -> "GitHub"）；單字元太雜，不啟用。
        // 只在比對文字夠短時啟用，否則長網址（含隨機 id）容易湊巧湊出子序列、誤判成強匹配。
        if q.count < 2 || t.count > subsequenceMaxLength { return -1 }
        var ti = 0, total = 0, streak = 0
        for ch in q {
            guard let at = t[ti...].firstIndex(of: ch) else { return -1 }
            streak = at == ti ? streak + 1 : 0
            total += 1 + streak * 2 + (isBoundary(t, at) ? 6 : 0)
            ti = at + 1
        }
        return total
    }

    /// 以空白切開的每個關鍵字都要符合，分數相加。空查詢回傳 0。
    static func score(query: String, in text: String) -> Int {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if terms.isEmpty { return 0 }
        var total = 0
        for term in terms {
            let s = score(term: term, in: text)
            if s < 0 { return -1 }
            total += s
        }
        return total
    }

    private static func indexOf(_ q: [Character], in t: [Character], from: Int) -> Int? {
        guard q.count <= t.count else { return nil }
        for i in from...(t.count - q.count) where Array(t[i..<(i + q.count)]) == q { return i }
        return nil
    }
}
