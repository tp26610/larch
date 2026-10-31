import Foundation
import Testing
@testable import Larch

@MainActor
struct PinStoreTests {
    private func url(_ s: String) -> URL { URL(string: s)! }

    private func ids(_ store: PinStore, parent: UUID? = nil) -> [UUID] { store.children(of: parent).map(\.id) }

    @Test func addTabsAndFoldersAtRootAndInFolder() {
        let s = PinStore()
        let f = s.addFolder(parent: nil)
        let a = s.addTab(url: url("https://a.com"), title: "A", parent: nil)
        let b = s.addTab(url: url("https://b.com"), title: "B", parent: f.id)
        #expect(ids(s) == [f.id, a.id])
        #expect(ids(s, parent: f.id) == [b.id])
        #expect(s.find(b.id)?.parent?.id == f.id)
    }

    @Test func insertIndexIsClamped() {
        let s = PinStore()
        let a = s.addTab(url: url("https://a.com"), title: "A", parent: nil, index: 99)
        let b = s.addTab(url: url("https://b.com"), title: "B", parent: nil, index: -5)
        #expect(ids(s) == [b.id, a.id])
    }

    @Test func addingToFolderExpandsIt() {
        let s = PinStore()
        let f = s.addFolder(parent: nil)
        s.setExpanded(f.id, false)
        s.addTab(url: url("https://a.com"), title: "A", parent: f.id)
        #expect(f.expanded)
    }

    @Test func moveWithinSameParentAccountsForRemoval() {
        let s = PinStore()
        let a = s.addTab(url: url("https://a.com"), title: "A", parent: nil)
        let b = s.addTab(url: url("https://b.com"), title: "B", parent: nil)
        let c = s.addTab(url: url("https://c.com"), title: "C", parent: nil)
        // 把 A 放到 C 之後（index 3，含自己時的插入位置）。
        #expect(s.move(a.id, toParent: nil, index: 3))
        #expect(ids(s) == [b.id, c.id, a.id])
    }

    @Test func moveAcrossLevels() {
        let s = PinStore()
        let f = s.addFolder(parent: nil)
        let a = s.addTab(url: url("https://a.com"), title: "A", parent: nil)
        #expect(s.move(a.id, toParent: f.id, index: 0))
        #expect(ids(s) == [f.id])
        #expect(ids(s, parent: f.id) == [a.id])
        #expect(s.move(a.id, toParent: nil, index: 0))
        #expect(ids(s) == [a.id, f.id])
    }

    @Test func cannotMoveFolderIntoItselfOrDescendant() {
        let s = PinStore()
        let outer = s.addFolder(name: "outer", parent: nil)
        let inner = s.addFolder(name: "inner", parent: outer.id)
        #expect(!s.move(outer.id, toParent: outer.id, index: 0))
        #expect(!s.move(outer.id, toParent: inner.id, index: 0))
        #expect(s.isDescendant(inner.id, of: outer.id))
        #expect(!s.isDescendant(outer.id, of: inner.id))
        #expect(ids(s) == [outer.id])
    }

    @Test func cannotMoveIntoTabOrMissingNode() {
        let s = PinStore()
        let a = s.addTab(url: url("https://a.com"), title: "A", parent: nil)
        let b = s.addTab(url: url("https://b.com"), title: "B", parent: nil)
        #expect(!s.move(a.id, toParent: b.id, index: 0))
        #expect(!s.move(UUID(), toParent: nil, index: 0))
        #expect(!s.move(a.id, toParent: UUID(), index: 0))
    }

    @Test func removeFolderTakesChildren() {
        let s = PinStore()
        let f = s.addFolder(parent: nil)
        let a = s.addTab(url: url("https://a.com"), title: "A", parent: f.id)
        #expect(s.remove(f.id)?.id == f.id)
        #expect(s.find(a.id) == nil)
        #expect(s.remove(f.id) == nil)
    }

    @Test func deleteFolderHoistsChildrenInPlace() {
        let s = PinStore()
        let before = s.addTab(url: url("https://x.com"), title: "X", parent: nil)
        let f = s.addFolder(parent: nil)
        let after = s.addTab(url: url("https://y.com"), title: "Y", parent: nil)
        let a = s.addTab(url: url("https://a.com"), title: "A", parent: f.id)
        let b = s.addTab(url: url("https://b.com"), title: "B", parent: f.id)
        s.deleteFolder(f.id)
        #expect(ids(s) == [before.id, a.id, b.id, after.id])
    }

    @Test func deleteFolderIgnoresTabs() {
        let s = PinStore()
        let a = s.addTab(url: url("https://a.com"), title: "A", parent: nil)
        s.deleteFolder(a.id)
        #expect(ids(s) == [a.id])
    }

    @Test func visibleSkipsCollapsedChildrenAndReportsDepth() {
        let s = PinStore()
        let f = s.addFolder(parent: nil)
        let inner = s.addFolder(parent: f.id)
        let a = s.addTab(url: url("https://a.com"), title: "A", parent: inner.id)
        #expect(s.visible().map(\.node.id) == [f.id, inner.id, a.id])
        #expect(s.visible().map(\.depth) == [0, 1, 2])
        s.setExpanded(inner.id, false)
        #expect(s.visible().map(\.node.id) == [f.id, inner.id])
    }

    @Test func renameTrimsAndIgnoresBlank() {
        let s = PinStore()
        let f = s.addFolder(name: "Old", parent: nil)
        s.rename(f.id, to: "  New  ")
        #expect(f.title == "New")
        s.rename(f.id, to: "   ")
        #expect(f.title == "New")
    }

    @Test func onChangeFiresOnStructuralChangesOnly() {
        let s = PinStore()
        var count = 0
        s.onChange = { count += 1 }
        let f = s.addFolder(parent: nil)
        #expect(count == 1)
        s.setExpanded(f.id, true)   // 值沒變
        #expect(count == 1)
        s.setExpanded(f.id, false)
        #expect(count == 2)
    }

    @Test func isAwayIgnoresWWWTrailingSlashQueryAndFragment() {
        #expect(!PinStore.isAway(pinURL: "https://example.com/a", current: url("https://www.example.com/a/?x=1#f")))
        #expect(PinStore.isAway(pinURL: "https://example.com/a", current: url("https://example.com/b")))
        #expect(PinStore.isAway(pinURL: "https://example.com", current: url("https://other.com")))
    }

    @Test func isAwayFalseWhenUnknown() {
        #expect(!PinStore.isAway(pinURL: "https://example.com", current: nil))
        #expect(!PinStore.isAway(pinURL: "https://example.com", current: url("about:blank")))
        #expect(!PinStore.isAway(pinURL: nil, current: url("https://example.com")))
    }

    @Test func rememberUpdatesOnlyWhileOnPinnedPage() {
        let s = PinStore()
        let a = s.addTab(url: url("https://a.com/p"), title: "Old", parent: nil)
        s.remember(a.id, title: "Away", favicon: nil, at: url("https://a.com/other"))
        #expect(a.title == "Old")
        s.remember(a.id, title: "Fresh", favicon: Data([1]), at: url("https://a.com/p"))
        #expect(a.title == "Fresh")
        #expect(a.favicon == Data([1]))
    }

    @Test func replaceURLUpdatesTabButRejectsFoldersAndNonHTTP() {
        let s = PinStore()
        let a = s.addTab(url: url("https://a.com"), title: "A", parent: nil)
        let f = s.addFolder(parent: nil)
        s.replaceURL(a.id, url: url("https://b.com/x"), title: "B", favicon: nil)
        #expect(a.url == "https://b.com/x")
        #expect(a.title == "B")
        s.replaceURL(a.id, url: url("file:///etc/passwd"), title: "Evil", favicon: nil)
        #expect(a.url == "https://b.com/x")
        s.replaceURL(f.id, url: url("https://c.com"), title: "C", favicon: nil)
        #expect(f.url == nil)
    }
}
