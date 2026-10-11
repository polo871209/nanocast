import Foundation

struct WindowLayoutDisplay: Codable, Hashable, Sendable {
    var uuid: String
    var name: String

    init(uuid: String, name: String) {
        self.uuid = uuid
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case uuid, name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decode(String.self, forKey: .uuid)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Display"
    }
}
