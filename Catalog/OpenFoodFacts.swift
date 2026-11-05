import Foundation

struct OFFProduct: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let brand: String
    let amountUnit: String
    let kcal: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let fiber: Double?
    let sugars: Double?
    let salt: Double?
    let grade: String?
    let ingredients: String?
    let imageURL: String?
    let allergens: [String]
    let traces: [String]
    var sourceURL: URL? { URL(string: "https://world.openfoodfacts.org/product/\(id)") }
    var isExample: Bool { false }

    init?(record: [String: Any]) {
        func field(_ keys: String...) -> String? {
            keys.compactMap { record[$0] as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        }
        guard let code = field("code"), (1...32).contains(code.count), code.allSatisfy({ $0.isASCII && $0.isNumber }),
              let name = field("product_name_en", "product_name") else { return nil }
        let nutrients = record["nutriments"] as? [String: Any] ?? [:]
        func number(_ key: String) -> Double? {
            let raw = nutrients[key]
            let value = (raw as? NSNumber)?.doubleValue ?? (raw as? String).flatMap(Double.init)
            return value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        }
        id = code
        self.name = name
        let brands = (record["brands"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        brand = field("brands") ?? brands.filter { !$0.isEmpty }.joined(separator: ", ")
        let basis = field("nutrition_data_per")?.lowercased().filter { !$0.isWhitespace }
        let packageUnit = field("product_quantity_unit")?.lowercased()
        let volume = ["ml", "cl", "dl", "l", "fl oz", "fl. oz."]
        // OFF commonly stores both per-100-ml and per-100-g values under *_100g keys.
        let quantity = (field("quantity") ?? field("serving_size") ?? "").lowercased()
        let liquidPack = quantity.range(of: #"[0-9]\s*(ml|cl|dl|l|fl\.?\s*oz)\b"#, options: .regularExpression) != nil
        switch basis {
        case "100ml": amountUnit = "ml"
        case "100g": amountUnit = "g"
        default: amountUnit = volume.contains(packageUnit ?? "") || (packageUnit == nil && liquidPack) ? "ml" : "g"
        }
        kcal = number("energy-kcal_100g") ?? (number("energy-kj_100g") ?? number("energy_100g")).map { $0 / 4.184 }
        protein = number("proteins_100g")
        carbs = number("carbohydrates_100g")
        fat = number("fat_100g")
        fiber = number("fiber_100g")
        sugars = number("sugars_100g")
        salt = number("salt_100g")
        let score = field("nutriscore_grade")?.lowercased()
        grade = score.flatMap { ["a", "b", "c", "d", "e"].contains($0) ? $0.uppercased() : nil }
        ingredients = field("ingredients_text_en") ?? ((field("lang") == "en") ? field("ingredients_text") : nil)
        imageURL = field("image_front_small_url")
        allergens = record["allergens_tags"] as? [String] ?? []
        traces = record["traces_tags"] as? [String] ?? []
    }
}

enum CatalogFailure: LocalizedError {
    case busy, invalid, notFound, unavailable
    var errorDescription: String? {
        switch self {
        case .busy: "Too many searches. Wait a minute or choose a saved product."
        case .invalid: "The catalog returned an unreadable product. Please try again."
        case .notFound: "Open Food Facts does not have this barcode yet."
        case .unavailable: "Open Food Facts is unavailable. You can still use the offline catalog."
        }
    }
}

enum FoodCatalog {
    static let fields = "code,product_name,product_name_en,brands,nutriments,allergens_tags,traces_tags,nutriscore_grade,nutrition_data_per,quantity,product_quantity_unit,serving_size,lang,ingredients_text_en,ingredients_text,image_front_small_url"
    static func parse(_ data: Data, barcode: Bool) throws -> [OFFProduct] {
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CatalogFailure.invalid }
        if barcode {
            if response["status"] as? Int == 0 { throw CatalogFailure.notFound }
            guard let raw = response["product"] as? [String: Any], let product = OFFProduct(record: raw) else { throw CatalogFailure.invalid }
            return [product]
        }
        guard let records = (response["hits"] ?? response["products"]) as? [[String: Any]] else {
            throw CatalogFailure.invalid
        }
        var codes = Set<String>()
        return records.compactMap(OFFProduct.init).filter { codes.insert($0.id).inserted }
    }

    static func lookup(_ query: String) async throws -> [OFFProduct] {
        let isBarcode = query.allSatisfy { $0.isASCII && $0.isNumber }
        var url = URLComponents()
        url.scheme = "https"
        url.host = isBarcode ? "world.openfoodfacts.org" : "search.openfoodfacts.org"
        url.path = isBarcode ? "/api/v2/product/\(query).json" : "/search"
        var items = [URLQueryItem(name: "fields", value: fields)]
        if !isBarcode {
            items += [.init(name: "q", value: query), .init(name: "langs", value: "en"),
                      .init(name: "page_size", value: "8"), .init(name: "sort_by", value: "-unique_scans_n")]
        }
        url.queryItems = items
        guard let endpoint = url.url else { throw CatalogFailure.invalid }
        var request = URLRequest(url: endpoint, timeoutInterval: 18)
        let app = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "FoodCatalog"
        request.setValue("\(app)/1.0 (iOS; \(Bundle.main.bundleIdentifier ?? app))", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CatalogFailure.invalid }
        if http.statusCode == 429 { throw CatalogFailure.busy }
        if http.statusCode == 404 && isBarcode { throw CatalogFailure.notFound }
        guard (200..<300).contains(http.statusCode) else { throw CatalogFailure.unavailable }
        return try parse(data, barcode: isBarcode)
    }

    private static let key = "off.catalog.cache.v1"
    static func offline() -> [OFFProduct] {
        let starter = Bundle.main.url(forResource: "StarterCatalog", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }.flatMap { try? parse($0, barcode: false) } ?? []
        #if DEBUG && targetEnvironment(simulator)
        if ScreenshotLaunch.active { return starter }
        #endif
        let cached = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([OFFProduct].self, from: $0) } ?? []
        var codes = Set<String>()
        return (cached + starter).filter { codes.insert($0.id).inserted }
    }

    static func remember(_ products: [OFFProduct]) {
        guard !products.isEmpty else { return }
        var codes = Set<String>()
        let recent = (products + offline()).filter { codes.insert($0.id).inserted }.prefix(100)
        if let data = try? JSONEncoder().encode(Array(recent)) { UserDefaults.standard.set(data, forKey: key) }
    }
}
