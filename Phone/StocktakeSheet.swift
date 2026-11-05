import SwiftUI

struct StocktakeSheet: View {
    @ObservedObject var stock: ShelfStock
    @State private var expected: [ShelfBatch]
    @State private var counts: [UUID: String] = [:]
    @State private var receipt: StocktakeRecord?
    @FocusState private var focused: UUID?
    @Environment(\.dismiss) private var dismiss
    init(stock: ShelfStock) { self.stock = stock; _expected = State(initialValue: ShelfStock.nearest(stock.archive.batches)) }
    private var validCounts: [UUID: Int] {
        counts.compactMapValues { text in
            guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(text), (0...9999).contains(value) else { return nil }
            return value
        }
    }
    var body: some View {
        NavigationStack {
            if let receipt {
                StocktakeReceipt(check: receipt)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            } else {
                List {
                    Section {
                        Text("Count the packs you actually have").font(.title2.bold())
                        Text("Check each batch in your kitchen. Enter the actual count, or tap Matches. Enter 0 for an empty batch. Nothing changes until you save.")
                        Text("\(validCounts.count) of \(expected.count) batches checked").font(.headline).foregroundStyle(ShelfInk.blue)
                    }
                    ForEach(expected) { batch in
                        Section {
                            Text(batch.product.name).font(.headline)
                            Text("\(batch.place.rawValue) · \(batch.expiryLabel)").font(.caption)
                            HStack {
                                Text("Recorded: \(batch.quantity)")
                                Spacer()
                                Button("Matches") { counts[batch.id] = String(batch.quantity); focused = nil }
                                    .buttonStyle(.bordered).accessibilityIdentifier("stocktake.match." + batch.id.uuidString)
                            }
                            TextField("Actual pack count", text: Binding(get: { counts[batch.id] ?? "" }, set: { counts[batch.id] = $0 }))
                                .keyboardType(.numberPad).focused($focused, equals: batch.id)
                                .accessibilityIdentifier("stocktake.count." + batch.id.uuidString)
                            if let count = validCounts[batch.id] {
                                Text(count == batch.quantity ? "Matches your shelf record" : "Correction: \((count - batch.quantity).formatted(.number.sign(strategy: .always()))) packs")
                                    .font(.caption.bold()).foregroundStyle(ShelfInk.blue)
                            }
                        }
                    }
                    if let problem = stock.problem { Section { Text(problem).foregroundStyle(.red) } }
                    Section {
                        Button("Save stocktake") {
                            guard stock.completeStocktake(expected: expected, counts: validCounts) else { return }
                            receipt = stock.archive.stocktakes.last
                        }.buttonStyle(ShelfAction()).disabled(expected.isEmpty || validCounts.count != expected.count)
                            .accessibilityIdentifier("stocktake.save")
                    } footer: { Text("Corrections are saved as Counted movements in Diary. They are not treated as used or discarded products. You can undo the latest movement for a batch there.") }
                }.scrollContentBackground(.hidden).background(ShelfInk.paper)
                    .navigationTitle("Stocktake").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                        ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = nil } }
                    }
            }
        }
    }
}

struct StocktakeReceipt: View {
    let check: StocktakeRecord
    var body: some View {
        List {
            Section {
                Label("Stocktake saved", systemImage: "checkmark.seal.fill").font(.title2.bold()).foregroundStyle(ShelfInk.blue)
                Text(check.time, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                LabeledContent("Batches checked", value: "\(check.counts.count)")
                LabeledContent("Total correction", value: "\(check.difference.formatted(.number.sign(strategy: .always()))) packs")
            } footer: { Text("This is the record of what you counted at the time. Later movements and undos may change current stock.") }
            ForEach(check.counts) { count in
                VStack(alignment: .leading, spacing: 6) {
                    Text(count.batch.product.name).font(.headline)
                    Text(count.batch.place.rawValue + " · " + count.batch.expiryLabel).font(.caption)
                    Text("\(count.batch.quantity) recorded → \(count.actual) counted")
                }
            }
        }.scrollContentBackground(.hidden).background(ShelfInk.paper)
            .navigationTitle("Stocktake result").navigationBarTitleDisplayMode(.inline)
    }
}
