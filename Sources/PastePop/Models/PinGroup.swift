import Foundation

struct PinGroup: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

enum PinGroupSelection: Hashable {
    case all
    case ungrouped
    case group(UUID)
}
