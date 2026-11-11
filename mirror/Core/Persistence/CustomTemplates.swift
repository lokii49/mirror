import Foundation

/// A template the person wrote: a name and the text a new entry starts with.
struct CustomTemplate: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var text: String
}

/// The person's own templates, kept on this device only (no CloudKit schema), sealed with the
/// journal key like Write's drafts: they are their words. Delete Everything removes them.
enum CustomTemplateStore {
    static let key = "mirror.customTemplates.v1"

    enum LoadResult: Equatable {
        case templates([CustomTemplate])
        /// Saved templates exist but can't be read yet (key not available). Nothing may be
        /// written then, or they'd be lost.
        case unavailable
    }

    static func load(defaults: UserDefaults = WriteDraftStore.storage,
                     crypto: WriteDraftStore.Crypto = .live) -> LoadResult {
        guard let sealed = defaults.data(forKey: key) else { return .templates([]) }
        guard let opened = crypto.open(sealed),
              let list = try? JSONDecoder().decode([CustomTemplate].self, from: opened) else { return .unavailable }
        return .templates(list)
    }

    /// The templates to offer, or none while they can't be read.
    static func readable(defaults: UserDefaults = WriteDraftStore.storage,
                         crypto: WriteDraftStore.Crypto = .live) -> [CustomTemplate] {
        if case .templates(let list) = load(defaults: defaults, crypto: crypto) { return list }
        return []
    }

    /// False (and nothing changed) when the list can't be sealed.
    @discardableResult
    static func save(_ templates: [CustomTemplate], defaults: UserDefaults = WriteDraftStore.storage,
                     crypto: WriteDraftStore.Crypto = .live) -> Bool {
        if templates.isEmpty {
            defaults.removeObject(forKey: key)
            return true
        }
        guard let data = try? JSONEncoder().encode(templates), let sealed = crypto.seal(data) else { return false }
        defaults.set(sealed, forKey: key)
        return true
    }

    /// Delete Everything.
    static func erase(defaults: UserDefaults = WriteDraftStore.storage) {
        defaults.removeObject(forKey: key)
    }
}
