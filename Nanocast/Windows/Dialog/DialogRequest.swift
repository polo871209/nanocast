import Foundation

struct DialogAction {
    enum Role {
        case standard
        case destructive
        case cancel
    }

    let title: String
    var role: Role = .standard
}

enum DialogTone: Sendable {
    case neutral
    case success
    case danger
}

struct DialogRequest {
    let title: String
    var message: String?
    let symbol: String?
    var tone: DialogTone = .neutral
    var actions: [DialogAction]
    var defaultIndex: Int
    var cancelIndex: Int
    var accessory: DialogAccessory?
}

enum DialogAccessory {
    case volume(VolumeState)
}
