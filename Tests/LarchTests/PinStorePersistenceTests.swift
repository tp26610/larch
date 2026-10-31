import Foundation
import Testing
@testable import Larch

@MainActor
struct PinStorePersistenceTests {
    private func tempStorage() -> Storage {
        Storage(directory: FileManager.default.temporaryDirectory.appendingPathComponent("larch-test-\(UUID().uuidString)"))
    }

    private func writeRaw(_ text: String, to storage: Storage) throws {
        try FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
        try text.data(using: .utf8)!.write(to: storage.directory.appendingPathComponent(PinStore.fileName))
    }

    @Test func roundTripKeepsTreeAndFields() {
        let storage = tempStorage()
        defer { try? FileManager.default.removeItem(at: storage.directory) }
        let s = PinStore(storage: storage)
        let f = s.addFolder(name: "Work", parent: nil)
        let a = s.addTab(url: URL(string: "https://a.com/x")!, title: "A", parent: f.id)
        a.favicon = Data([1, 2, 3])
        s.setExpanded(f.id, false)
        s.addTab(url: URL(string: "https://b.com")!, title: "B", parent: nil)
        s.save()

        let loaded = PinStore(storage: storage)
        #expect(loaded.roots.map(\.title) == ["Work", "B"])
        let folder = loaded.roots[0]
        #expect(folder.isFolder && !folder.expanded)
        #expect(folder.children.map(\.title) == ["A"])
        #expect(folder.children[0].url == "https://a.com/x")
        #expect(folder.children[0].favicon == Data([1, 2, 3]))
        #expect(loaded.find(a.id)?.parent?.id == f.id)
    }

    @Test func flushWritesPendingChange() {
        let storage = tempStorage()
        defer { try? FileManager.default.removeItem(at: storage.directory) }
        let s = PinStore(storage: storage)
        s.addTab(url: URL(string: "https://a.com")!, title: "A", parent: nil)
        s.flush()   // 不等 Debouncer 的延遲
        #expect(PinStore(storage: storage).roots.map(\.title) == ["A"])
    }

    @Test func missingFileLoadsEmpty() {
        let storage = tempStorage()
        #expect(PinStore(storage: storage).roots.isEmpty)
    }

    @Test func corruptFilesLoadEmpty() throws {
        for junk in ["", "not json at all", "{\"version\":1,\"roots\":", "[1,2,3]", "{\"version\":1,\"roots\":[{\"title\":5}]}"] {
            let storage = tempStorage()
            defer { try? FileManager.default.removeItem(at: storage.directory) }
            try writeRaw(junk, to: storage)
            #expect(PinStore(storage: storage).roots.isEmpty, "壞檔應載入為空樹：\(junk)")
        }
    }

    @Test func unsupportedVersionLoadsEmpty() throws {
        let storage = tempStorage()
        defer { try? FileManager.default.removeItem(at: storage.directory) }
        try writeRaw(#"{"version":2,"roots":[{"id":"\#(UUID().uuidString)","kind":"tab","title":"A","url":"https://a.com","expanded":true,"children":[]}]}"#, to: storage)
        #expect(PinStore(storage: storage).roots.isEmpty)
    }

    @Test func loadDropsNonHTTPTabsButKeepsFolders() throws {
        let storage = tempStorage()
        defer { try? FileManager.default.removeItem(at: storage.directory) }
        func tab(_ title: String, _ url: String?) -> String {
            let u = url.map { "\"\($0)\"" } ?? "null"
            return #"{"id":"\#(UUID().uuidString)","kind":"tab","title":"\#(title)","url":\#(u),"expanded":true,"children":[]}"#
        }
        let folder = #"{"id":"\#(UUID().uuidString)","kind":"folder","title":"F","expanded":true,"children":[\#(tab("ok", "https://ok.com")),\#(tab("file", "file:///etc/passwd")),\#(tab("js", "javascript:alert(1)")),\#(tab("nil", nil))]}"#
        try writeRaw(#"{"version":1,"roots":[\#(folder),\#(tab("top-bad", "mailto:a@b.com")),\#(tab("top-ok", "http://x.com"))]}"#, to: storage)

        let s = PinStore(storage: storage)
        #expect(s.roots.map(\.title) == ["F", "top-ok"])
        #expect(s.roots[0].children.map(\.title) == ["ok"])
    }
}
