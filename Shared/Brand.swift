import SwiftUI

enum Brand {
    static let name = "ShelfCue"
    static let group = "group.app.shelfcue.food"
    static let route = "shelfcue"
    static let widget = "app.shelfcue.food.summary"
    static let section = "Pantry queue"
    static let hint = "Stock a batch on iPhone."
    static let blurb = "The next pantry batch to check, with quantity and storage location."
    static let symbol = "shippingbox"
    static let accent = Color(red: 0.8706, green: 0.9569, blue: 0.4941)
    static let ground = Color(red: 0.0980, green: 0.1765, blue: 0.5020)
    static let preview = CompanionSnapshot(title: "Pantry check", value: "Spaghetti Nº5", detail: "2 packs · Cupboard · Nov 9", items: [], updated: .now)
}
