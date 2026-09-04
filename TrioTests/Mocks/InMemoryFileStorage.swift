import Foundation
@testable import Trio

/// Keeps `SettingsManager`/`FileStorage` reads inside the test process instead of the
/// simulator's real Documents directory, whose `preferences.json` and `settings.json`
/// carry the developer's own on-device settings (curve, concentration, etc.) and leak
/// into any test that asserts a specific default.
final class InMemoryFileStorage: FileStorage {
    private var store: [String: Data] = [:]
    private let queue = DispatchQueue(label: "InMemoryFileStorage.queue")

    func save<Value: JSON>(_ value: Value, as name: String) {
        queue.sync { store[name] = encode(value) }
    }

    func saveAsync<Value: JSON>(_ value: Value, as name: String) async {
        save(value, as: name)
    }

    func retrieve<Value: JSON>(_ name: String, as type: Value.Type) -> Value? {
        queue.sync { decode(store[name], as: type) }
    }

    func retrieveAsync<Value: JSON>(_ name: String, as type: Value.Type) async -> Value? {
        retrieve(name, as: type)
    }

    func retrieveRaw(_ name: String) -> RawJSON? {
        queue.sync { store[name].flatMap { String(data: $0, encoding: .utf8) } }
    }

    func retrieveRawAsync(_ name: String) async -> RawJSON? {
        retrieveRaw(name)
    }

    func append<Value: JSON>(_ newValue: Value, to name: String) {
        queue.sync {
            var values = decode(store[name], as: [Value].self) ?? []
            values.append(newValue)
            store[name] = encode(values)
        }
    }

    func append<Value: JSON>(_ newValues: [Value], to name: String) {
        queue.sync {
            var values = decode(store[name], as: [Value].self) ?? []
            values.append(contentsOf: newValues)
            store[name] = encode(values)
        }
    }

    func append<Value: JSON, T: Equatable>(_ newValue: Value, to name: String, uniqBy keyPath: KeyPath<Value, T>) {
        queue.sync {
            var values = decode(store[name], as: [Value].self) ?? []
            if values.first(where: { $0[keyPath: keyPath] == newValue[keyPath: keyPath] }) == nil {
                values.append(newValue)
            }
            store[name] = encode(values)
        }
    }

    func append<Value: JSON, T: Equatable>(_ newValues: [Value], to name: String, uniqBy keyPath: KeyPath<Value, T>) {
        queue.sync {
            var values = decode(store[name], as: [Value].self) ?? []
            for newValue in newValues where values.first(where: { $0[keyPath: keyPath] == newValue[keyPath: keyPath] }) == nil {
                values.append(newValue)
            }
            store[name] = encode(values)
        }
    }

    func remove(_ name: String) {
        queue.sync { store.removeValue(forKey: name) }
    }

    func rename(_ name: String, to newName: String) {
        queue.sync { store[newName] = store.removeValue(forKey: name) }
    }

    func transaction(_ exec: (FileStorage) -> Void) {
        exec(self)
    }

    func urlFor(file _: String) -> URL? { nil }

    private func encode<Value: JSON>(_ value: Value) -> Data? {
        if let value = value as? RawJSON { return value.data(using: .utf8) }
        return try? JSONCoding.encoder.encode(value)
    }

    private func decode<Value: JSON>(_ data: Data?, as _: Value.Type) -> Value? {
        guard let data else { return nil }
        return try? JSONCoding.decoder.decode(Value.self, from: data)
    }
}
