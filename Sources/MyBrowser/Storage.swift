import Foundation

/// 存在 Application Support 的 JSON 檔。讀取容錯：檔案不存在、損壞、版本不符一律回傳 nil。
struct Storage {
    let directory: URL

    static var standard: Storage {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return Storage(directory: base.appendingPathComponent("MyBrowser", isDirectory: true))
    }

    func read<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func write<T: Encodable>(_ name: String, _ value: T) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            NSLog("MyBrowser: 寫入 \(name) 失敗：\(error.localizedDescription)")
        }
    }
}

/// 把頻繁的變更合併成一次延遲寫入。
@MainActor
final class Debouncer {
    private var work: DispatchWorkItem?
    private let delay: TimeInterval

    init(delay: TimeInterval = 0.5) { self.delay = delay }

    func schedule(_ block: @escaping @MainActor () -> Void) {
        work?.cancel()
        let item = DispatchWorkItem { MainActor.assumeIsolated(block) }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// 立刻執行尚未寫出的變更。
    func flush(_ block: @MainActor () -> Void) {
        guard work != nil else { return }
        work?.cancel()
        work = nil
        block()
    }
}
