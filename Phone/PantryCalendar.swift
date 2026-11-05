import SwiftUI

struct PantryCalendar: View {
    @ObservedObject var stock: ShelfStock
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start
    @State private var selected = ShelfDay(.now)
    @State private var note: PantryNote?
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.locale = Locale(identifier: "en_US"); result.firstWeekday = 2
        return result
    }
    private var days: [Date] {
        let count = calendar.range(of: .day, in: .month, for: month)!.count
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: month) }
    }
    private var padding: Int { (calendar.component(.weekday, from: month) + 5) % 7 }
    private var events: PantryDayEvents { PantryDayEvents(archive: stock.archive, day: selected) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Previous month")
                Spacer()
                Text(month, format: .dateTime.month(.wide).year()).font(.title3.bold())
                Spacer()
                Button { changeMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Next month")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(.caption.bold()).foregroundStyle(.secondary)
                }
                ForEach(0..<padding, id: \.self) { _ in Color.clear.frame(height: 48) }
                ForEach(days, id: \.self) { date in
                    let day = ShelfDay(date)
                    let marks = PantryDayEvents(archive: stock.archive, day: day)
                    Button { selected = day } label: {
                        VStack(spacing: 5) {
                            Text("\(day.day)").font(.subheadline.bold())
                            HStack(spacing: 3) {
                                Circle().fill(marks.batches.isEmpty ? .clear : Color.orange).frame(width: 5, height: 5)
                                Circle().fill(marks.scans.isEmpty ? .clear : ShelfInk.blue).frame(width: 5, height: 5)
                                Circle().fill(marks.hasActivity ? ShelfInk.navy : .clear).frame(width: 5, height: 5)
                            }
                        }.frame(maxWidth: .infinity, minHeight: 48)
                            .background(selected == day ? ShelfInk.lime : ShelfInk.label, in: RoundedRectangle(cornerRadius: 9))
                            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(day == ShelfDay(.now) ? ShelfInk.blue : .clear) }
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(day.label), \(marks.batches.count) package dates, \(marks.scans.count) barcode lookups, \(marks.movements.count + marks.notes.count + marks.stocktakes.count) diary entries")
                        .accessibilityAddTraits(selected == day ? .isSelected : [])
                }
            }
            HStack(spacing: 12) {
                legend("Package date", .orange); legend("Scan", ShelfInk.blue); legend("Diary", ShelfInk.navy)
            }
            Button("Today") { month = calendar.dateInterval(of: .month, for: .now)!.start; selected = ShelfDay(.now) }
                .font(.subheadline.bold()).frame(minHeight: 44)
            Divider()
            Text(selected.label).font(.title2.bold())
            Button { note = PantryNote(date: selected.date, text: "") } label: { Label("Add note for this day", systemImage: "square.and.pencil") }
                .buttonStyle(ShelfAction(secondary: true))
            if events.isEmpty {
                ContentUnavailableView("Nothing recorded", systemImage: "calendar", description: Text("Package dates, stock movements, scans and notes appear on their recorded day."))
            }
            if !events.batches.isEmpty {
                Text("Package dates").font(.headline)
                Text("Dates belong to batches still on your shelves. Always check the package before using a product.").font(.caption)
                ForEach(events.batches) { batch in
                    NavigationLink(value: batch.id) {
                        Label("\(batch.product.name) · \(batch.quantity) packs", systemImage: batch.place.icon)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(ShelfInk.label, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            }
            if !events.scans.isEmpty { Text("Barcode lookups").font(.headline) }
            ForEach(events.scans) { ScanRecordCard(scan: $0) }
            if !events.movements.isEmpty { Text("Stock movements").font(.headline) }
            ForEach(events.movements) { movement in
                VStack(alignment: .leading, spacing: 6) {
                    Label(movement.operation.rawValue, systemImage: movement.operation.symbol).font(.caption.bold()).foregroundStyle(ShelfInk.blue)
                    Text(movement.batch?.product.name ?? "Product").font(.headline)
                    Text("\(movement.before?.quantity ?? 0) → \(movement.after?.quantity ?? 0) packs").font(.subheadline)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(ShelfInk.label, in: RoundedRectangle(cornerRadius: 12))
            }
            ForEach(events.stocktakes) { check in
                NavigationLink { StocktakeReceipt(check: check) } label: { Label("Stocktake · \(check.counts.count) batches checked", systemImage: "checklist") }.padding(.vertical, 8)
            }
            ForEach(events.notes) { entry in
                Button { note = entry } label: { PantryNoteCard(note: entry) }.buttonStyle(.plain)
            }
        }.sheet(item: $note) { PantryNoteEditor(stock: stock, original: $0) }
    }
    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 6, height: 6); Text(text).font(.caption2) }
    }
    private func changeMonth(_ offset: Int) {
        if let next = calendar.date(byAdding: .month, value: offset, to: month) { month = next; selected = ShelfDay(next) }
    }
}
