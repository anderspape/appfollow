import Foundation

enum StorageJSONCodec {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode<T: Decodable>(_ type: T.Type, from payload: String?) -> T? {
        guard let payload,
              let data = payload.data(using: .utf8)
        else {
            return nil
        }
        return try? decoder.decode(T.self, from: data)
    }
}
