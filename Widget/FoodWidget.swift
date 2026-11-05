import SwiftUI
import WidgetKit

struct FoodEntry: TimelineEntry {
    let date: Date
    let summary: CompanionSnapshot
}
struct FoodProvider: TimelineProvider {
    func placeholder(in context: Context) -> FoodEntry {
        .init(date: .now, summary: Brand.preview)
    }
    func getSnapshot(in context: Context, completion: @escaping (FoodEntry) -> Void) {
        completion(.init(date: .now, summary: context.isPreview ? Brand.preview : CompanionSnapshot.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FoodEntry>) -> Void) {
        let now = Date()
        let nextDay = Calendar.current.dateInterval(of: .day, for: now)?.end ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [.init(date: now, summary: CompanionSnapshot.read())], policy: .after(nextDay)))
    }
}
struct WidgetFace: View {
    @Environment(\.widgetFamily) private var family
    let entry: FoodEntry
    var body: some View {
        let data = entry.summary
        VStack(alignment: .leading, spacing: 5) {
            Label(Brand.name.uppercased(), systemImage: Brand.symbol)
                .font(.caption2.monospaced().bold()).foregroundStyle(Brand.accent)
            Spacer(minLength: 2)
            Text(data.title).font(.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
            Text(data.value).font(.system(.title2, design: .rounded, weight: .bold)).minimumScaleFactor(0.7).lineLimit(2)
            if family == .systemMedium {
                Text(data.detail).font(.caption).lineLimit(2)
                if let first = data.items.first { Text(first.title + " · " + first.detail).font(.caption2).lineLimit(1).foregroundStyle(Brand.accent) }
            } else {
                Text(data.detail).font(.caption2).lineLimit(2)
            }
            if data.updated > .distantPast && !Calendar.current.isDate(data.updated, inSameDayAs: entry.date) {
                Text("As of " + data.updated.formatted(.dateTime.month(.abbreviated).day().locale(Locale(identifier: "en_US")))).font(.caption2.bold()).foregroundStyle(Brand.accent)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .containerBackground(Brand.ground, for: .widget)
        .widgetURL(URL(string: Brand.route + "://dashboard"))
    }
}
@main
struct FoodWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Brand.widget, provider: FoodProvider()) { entry in WidgetFace(entry: entry) }
            .configurationDisplayName(Brand.section)
            .description(Brand.blurb)
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
