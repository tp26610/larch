import AppKit

/// 釘選區的節點：資料夾（可巢狀）或釘選的 Tab。最上層可以是單獨的 Tab，不一定要在資料夾裡。
/// 釘選的 Tab 記住一個網址；關掉開著的 Tab 後節點仍在（顯示為灰色），點一下用該網址重新開啟。
final class PinNode: Codable {
    enum Kind: String, Codable { case folder, tab }

    let id: UUID
    var kind: Kind
    var title: String
    var url: String?
    var expanded: Bool
    var children: [PinNode]
    /// 縮圖 PNG（讓灰色的釘選列也有 favicon）。
    var favicon: Data?

    init(id: UUID = UUID(), kind: Kind, title: String, url: String? = nil, expanded: Bool = true, children: [PinNode] = [], favicon: Data? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.url = url
        self.expanded = expanded; self.children = children; self.favicon = favicon
    }

    var isFolder: Bool { kind == .folder }
}

private struct PinFile: Codable {
    var version = 1
    var roots: [PinNode]
}

/// 釘選與資料夾的樹。存 pins.json，變更後延遲寫入。
@MainActor
final class PinStore {
    static let fileName = "pins.json"

    private let storage: Storage?
    private let saver = Debouncer()
    private(set) var roots: [PinNode]
    /// 任何結構或內容變更（含展開/收合）。
    var onChange: (() -> Void)?

    init(storage: Storage? = nil) {
        self.storage = storage
        let file = storage?.read(Self.fileName, as: PinFile.self)
        roots = (file?.version == 1 ? file?.roots : nil).map(Self.sanitized) ?? []
    }

    /// 只留 http(s) 的 Tab 節點；資料夾保留。
    private static func sanitized(_ nodes: [PinNode]) -> [PinNode] {
        nodes.compactMap { n in
            if n.isFolder { n.children = sanitized(n.children); return n }
            guard InputNormalizer.isHTTP(n.url.flatMap(URL.init(string:))) else { return nil }
            n.children = []
            return n
        }
    }

    // MARK: 查詢

    struct Location { let node: PinNode; let parent: PinNode?; let index: Int }

    func find(_ id: UUID) -> Location? { Self.find(id, in: roots, parent: nil) }

    private static func find(_ id: UUID, in nodes: [PinNode], parent: PinNode?) -> Location? {
        for (i, n) in nodes.enumerated() {
            if n.id == id { return Location(node: n, parent: parent, index: i) }
            if n.isFolder, let hit = find(id, in: n.children, parent: n) { return hit }
        }
        return nil
    }

    func children(of parent: UUID?) -> [PinNode] {
        guard let parent else { return roots }
        return find(parent)?.node.children ?? []
    }

    /// 依畫面順序（深度優先，略過收合資料夾的內容）。
    func visible() -> [(node: PinNode, depth: Int)] {
        var out: [(PinNode, Int)] = []
        func walk(_ nodes: [PinNode], _ depth: Int) {
            for n in nodes {
                out.append((n, depth))
                if n.isFolder, n.expanded { walk(n.children, depth + 1) }
            }
        }
        walk(roots, 0)
        return out
    }

    /// 全部的釘選 Tab 節點（含收合資料夾內）。
    var allTabs: [PinNode] {
        var out: [PinNode] = []
        func walk(_ nodes: [PinNode]) { for n in nodes { if n.isFolder { walk(n.children) } else { out.append(n) } } }
        walk(roots)
        return out
    }

    func isDescendant(_ id: UUID, of ancestor: UUID) -> Bool {
        guard let a = find(ancestor)?.node, a.isFolder else { return false }
        return Self.find(id, in: a.children, parent: a) != nil
    }

    // MARK: 變更

    private func changed() {
        saver.schedule { [weak self] in self?.save() }
        onChange?()
    }

    @discardableResult
    func addFolder(name: String = "New Folder", parent: UUID?, index: Int? = nil) -> PinNode {
        let node = PinNode(kind: .folder, title: name)
        insert(node, parent: parent, index: index)
        return node
    }

    @discardableResult
    func addTab(url: URL, title: String, parent: UUID?, index: Int? = nil) -> PinNode {
        let node = PinNode(kind: .tab, title: title, url: url.absoluteString)
        insert(node, parent: parent, index: index)
        return node
    }

    private func insert(_ node: PinNode, parent: UUID?, index: Int?) {
        if let parent, let p = find(parent)?.node, p.isFolder {
            p.children.insert(node, at: min(max(0, index ?? p.children.count), p.children.count))
            p.expanded = true
        } else {
            roots.insert(node, at: min(max(0, index ?? roots.count), roots.count))
        }
        changed()
    }

    /// 移動節點（可跨層）。不能把資料夾放進自己底下。回傳是否成功。
    @discardableResult
    func move(_ id: UUID, toParent parent: UUID?, index: Int) -> Bool {
        guard let loc = find(id) else { return false }
        if let parent {
            guard parent != id, !isDescendant(parent, of: id), find(parent)?.node.isFolder == true else { return false }
        }
        var idx = index
        if loc.parent?.id == parent, loc.index < idx { idx -= 1 }
        detach(loc)
        insert(loc.node, parent: parent, index: idx)
        return true
    }

    private func detach(_ loc: Location) {
        if let p = loc.parent { p.children.remove(at: loc.index) } else { roots.remove(at: loc.index) }
    }

    /// 移除節點（資料夾連同內容）。回傳被移除的節點。
    @discardableResult
    func remove(_ id: UUID) -> PinNode? {
        guard let loc = find(id) else { return nil }
        detach(loc)
        changed()
        return loc.node
    }

    /// 刪除資料夾，內容移到原位置的上一層。
    func deleteFolder(_ id: UUID) {
        guard let loc = find(id), loc.node.isFolder else { return }
        detach(loc)
        let siblingsParent = loc.parent
        for (i, c) in loc.node.children.enumerated() {
            if let p = siblingsParent { p.children.insert(c, at: loc.index + i) } else { roots.insert(c, at: loc.index + i) }
        }
        changed()
    }

    func rename(_ id: UUID, to name: String) {
        guard let n = find(id)?.node else { return }
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, n.title != t else { return }
        n.title = t
        changed()
    }

    func setExpanded(_ id: UUID, _ value: Bool) {
        guard let n = find(id)?.node, n.isFolder, n.expanded != value else { return }
        n.expanded = value
        changed()
    }

    /// 目前頁面是否已離開釘選的那一頁。只比 host（忽略 www.）+ path（忽略結尾斜線），query / fragment 不算；
    /// 目前網址未知或非 http(s)（載入中、空白）一律視為沒離開。
    static func isAway(pinURL: String?, current: URL?) -> Bool {
        guard let pin = pinURL.flatMap(URL.init(string:)), let cur = current, InputNormalizer.isHTTP(cur) else { return false }
        func key(_ u: URL) -> String {
            var host = (u.host ?? "").lowercased()
            if host.hasPrefix("www.") { host.removeFirst(4) }
            var path = u.path
            while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
            return host + (path.isEmpty ? "/" : path)
        }
        return key(pin) != key(cur)
    }

    /// 開著的 Tab 更新時順便記住「釘選那一頁」的標題與 favicon，不觸發畫面重建。
    /// Tab 已離開釘選頁（`url` 與節點網址不同頁）時不更新，節點的標題與 favicon 固定代表釘選的那一頁；
    /// 要改成目前這頁用 `replaceURL`。
    func remember(_ id: UUID, title: String?, favicon: Data?, at url: URL?) {
        guard let n = find(id)?.node, !Self.isAway(pinURL: n.url, current: url) else { return }
        var dirty = false
        if let title, !title.isEmpty, n.title != title { n.title = title; dirty = true }
        if let favicon, n.favicon != favicon { n.favicon = favicon; dirty = true }
        if dirty { saver.schedule { [weak self] in self?.save() } }
    }

    /// 明確把釘選頁換成目前這頁（Replace Pinned URL with Current）：網址、標題、favicon 一起更新。
    func replaceURL(_ id: UUID, url: URL, title: String, favicon: Data?) {
        guard let n = find(id)?.node, !n.isFolder, InputNormalizer.isHTTP(url) else { return }
        n.url = url.absoluteString
        if !title.isEmpty { n.title = title }
        if let favicon { n.favicon = favicon }
        changed()
    }

    func save() { storage?.write(Self.fileName, PinFile(roots: roots)) }
    func flush() { saver.flush { save() } }
}
