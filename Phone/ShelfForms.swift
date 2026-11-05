import SwiftUI

struct ShelfEditor: View {
    let product: OFFProduct
    let original: ShelfBatch?
    let commit: (ShelfBatch) -> Bool
    @State private var quantity: Int
    @State private var place: ShelfPlace
    @State private var dated: Bool
    @State private var expiry: Date
    @State private var note: String
    @State private var saveFailed = false
    @Environment(\.dismiss) private var dismiss

    init(product: OFFProduct, original: ShelfBatch? = nil, commit: @escaping (ShelfBatch) -> Bool) {
        self.product = product
        self.original = original
        self.commit = commit
        _quantity = State(initialValue: original?.quantity ?? 1)
        _place = State(initialValue: original?.place ?? .cupboard)
        _dated = State(initialValue: original?.expiry != nil)
        _expiry = State(initialValue: original?.expiry?.date ?? .now)
        _note = State(initialValue: original?.note ?? "")
    }

    #if DEBUG && targetEnvironment(simulator)
    init(product: OFFProduct, demoDraft: ShelfBatch, commit: @escaping (ShelfBatch) -> Bool) {
        self.product = product
        self.original = nil
        self.commit = commit
        _quantity = State(initialValue: demoDraft.quantity)
        _place = State(initialValue: demoDraft.place)
        _dated = State(initialValue: demoDraft.expiry != nil)
        _expiry = State(initialValue: demoDraft.expiry?.date ?? .now)
        _note = State(initialValue: demoDraft.note)
    }
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(product.name).font(.title3.bold())
                    if !product.brand.isEmpty { Text(product.brand).font(.subheadline) }
                } header: { Text("Product") }
                Section {
                    Stepper("Packs · \(quantity)", value: $quantity, in: 1...9999)
                    Picker("Location", selection: $place) {
                        ForEach(ShelfPlace.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                    }
                    Toggle("Record the package date", isOn: $dated)
                    if dated {
                        DatePicker("Package date", selection: $expiry, displayedComponents: .date)
                    }
                } header: { Text("Batch") } footer: {
                    Text("Use the date printed on the package. Leave it off for undated goods.")
                }
                Section("Note") {
                    TextField("e.g. The open pack is at the front", text: $note, axis: .vertical).lineLimit(2...5)
                }
                Section {
                    Button {
                        let batch = ShelfBatch(id: original?.id ?? UUID(), product: product, quantity: quantity,
                                               place: place, expiry: dated ? ShelfDay(expiry) : nil,
                                               note: note.trimmingCharacters(in: .whitespacesAndNewlines))
                        if commit(batch) { dismiss() } else { saveFailed = true }
                    } label: { Text(original == nil ? "Stock this batch" : "Save changes") }
                    .buttonStyle(ShelfAction()).accessibilityIdentifier("shelf.stock")
                }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden).background(ShelfInk.paper)
            .navigationTitle(original == nil ? "New batch" : "Edit batch").navigationBarTitleDisplayMode(.inline)
            .alert("Couldn’t save this batch", isPresented: $saveFailed) {
                Button("Close") {}
            } message: {
                Text("Check available storage. If the batch changed elsewhere, reopen its ticket and try again.")
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.tint(ShelfInk.blue).preferredColorScheme(.light)
    }
}

struct ShelfDetail: View {
    @ObservedObject var stock: ShelfStock
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var edit: ShelfBatch?
    @State private var units = 1
    @State private var confirmDiscard = false
    @State private var result: String?
    @State private var labelExpanded = false

    init(stock: ShelfStock, id: UUID) {
        self.stock = stock
        self.id = id
    }

    #if DEBUG && targetEnvironment(simulator)
    init(stock: ShelfStock, id: UUID, labelExpanded: Bool) {
        self.stock = stock
        self.id = id
        _labelExpanded = State(initialValue: labelExpanded)
    }
    #endif

    private var batch: ShelfBatch? { stock.archive.batches.first { $0.id == id } }

    var body: some View {
        ScrollView {
            if let batch {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        ShelfKicker(text: batch.place.rawValue).foregroundStyle(ShelfInk.lime)
                        Text(batch.product.name).font(.title.bold())
                        if !batch.product.brand.isEmpty { Text(batch.product.brand) }
                        Divider().overlay(.white.opacity(0.4))
                        Label("Packs in stock · \(batch.quantity)", systemImage: "shippingbox")
                        Label(batch.expiryLabel, systemImage: "calendar")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        .foregroundStyle(.white).background(ShelfInk.blue, in: RoundedRectangle(cornerRadius: 16))
                    if !batch.note.isEmpty { Text(batch.note).font(.body) }
                    HStack {
                        ShelfKicker(text: "Batch activity")
                        Spacer()
                        Button { edit = batch } label: { Label("Edit", systemImage: "pencil") }
                    }
                    Stepper("Packs · \(units)", value: $units, in: 1...batch.quantity)
                        .font(.headline).padding().background(ShelfInk.label, in: RoundedRectangle(cornerRadius: 12))
                    Button { move(.used, batch: batch) } label: { Label("Mark used · \(units)", systemImage: "fork.knife") }
                        .buttonStyle(ShelfAction()).accessibilityIdentifier("shelf.use")
                    Button { confirmDiscard = true } label: { Label("Discard · \(units)", systemImage: "minus.circle") }
                        .buttonStyle(ShelfAction(secondary: true))
                    if let result { Text(result).font(.subheadline.bold()).foregroundStyle(ShelfInk.blue) }
                    DisclosureGroup("Product label", isExpanded: $labelExpanded) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Barcode · " + batch.product.id).font(.caption.monospaced())
                            if let ingredients = batch.product.ingredients, !ingredients.isEmpty {
                                Text("Ingredients").font(.headline)
                                Text(ingredients)
                            } else {
                                Text("Ingredient details are missing from this catalog entry.").font(.subheadline)
                            }
                            if let url = batch.product.sourceURL {
                                Link("View on Open Food Facts ↗", destination: url)
                            }
                        }.padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding().background(ShelfInk.label, in: RoundedRectangle(cornerRadius: 12))
                }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
                .sheet(item: $edit) { original in
                    ShelfEditor(product: original.product, original: original) { updated in
                        guard stock.save(updated, replacing: original) else { return false }
                        units = min(units, updated.quantity)
                        result = nil
                        return true
                    }
                }
                .confirmationDialog(units == 1 ? "Discard one pack?" : "Discard \(units) packs?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) { move(.discarded, batch: batch) }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("This will be recorded in your diary.") }
            } else {
                ContentUnavailableView("This batch is off the shelf", systemImage: "tray",
                                       description: Text("Open Diary to see its movements."))
                Button("Back to shelves") { dismiss() }.buttonStyle(.bordered)
            }
        }.background(ShelfInk.paper).navigationTitle("Batch ticket").navigationBarTitleDisplayMode(.inline)
    }

    private func move(_ operation: StockOperation, batch: ShelfBatch) {
        let count = units
        guard stock.removeUnits(count, from: id, operation: operation) else { return }
        if batch.quantity == count { dismiss() }
        else {
            units = 1
            result = "\(operation.rawValue) · \(count). Recorded in Diary."
        }
    }
}

struct ShelfJournal: View {
    @ObservedObject var stock: ShelfStock
    @State private var pendingUndo: UUID?
    @State private var scope = "All"
    private var undoable: Set<UUID> {
        var batches = Set<UUID>()
        return Set(stock.archive.history.reversed().compactMap { event in
            guard let id = event.batch?.id, batches.insert(id).inserted else { return nil }
            return event.id
        })
    }
    private var visible: [StockMovement] {
        stock.archive.history.reversed().filter { scope == "All" || scope == $0.operation.rawValue }
    }

    var body: some View {
        let eligible = undoable
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                ShelfKicker(text: "Stock movements")
                Spacer()
                Menu {
                    Picker("Activity type", selection: $scope) {
                        ForEach(["All", "Stocked", "Used", "Discarded", "Adjusted", "Counted"], id: \.self) { Text($0) }
                    }
                } label: { Label(scope, systemImage: "line.3.horizontal.decrease.circle") }
            }
            if visible.isEmpty {
                ContentUnavailableView("No movements yet", systemImage: "tray",
                                       description: Text(scope == "All" ? "Stock a batch to start your diary. Using and discarding packs creates new entries." : "There are no entries for this activity yet."))
            }
            LazyVStack(spacing: 10) {
                ForEach(visible) { event in
                    if let batch = event.batch {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(event.operation.rawValue, systemImage: event.operation.symbol).font(.caption.bold())
                                Spacer()
                                Text(event.time.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(.init(identifier: "en_US"))))
                                    .font(.caption.monospaced())
                            }.foregroundStyle(ShelfInk.blue)
                            Text(batch.product.name).font(.headline)
                            Text(batch.place.rawValue + " · " + batch.expiryLabel).font(.subheadline)
                            if event.operation == .edited, let before = event.before, let after = event.after {
                                if before.place != after.place { Text("\(before.place.rawValue) → \(after.place.rawValue)").font(.caption) }
                                if before.expiry != after.expiry { Text("\(before.expiryLabel) → \(after.expiryLabel)").font(.caption) }
                                if before.note != after.note { Text("Note updated").font(.caption) }
                            }
                            HStack {
                                Text("\(event.before?.quantity ?? 0) → \(event.after?.quantity ?? 0) packs").font(.subheadline.monospacedDigit().bold())
                                Spacer()
                                if eligible.contains(event.id) {
                                    Button("Undo") { pendingUndo = event.id }.font(.subheadline).frame(minHeight: 44)
                                }
                            }
                        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                        .background(ShelfInk.label, in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(ShelfInk.line) }
                    }
                }
            }
        }
        .confirmationDialog("Undo this batch movement?", isPresented: Binding(get: { pendingUndo != nil },
                                                                                set: { if !$0 { pendingUndo = nil } }),
                            titleVisibility: .visible, presenting: pendingUndo) { id in
            Button("Undo movement", role: .destructive) { _ = stock.undo(id) }
            Button("Keep entry", role: .cancel) {}
        } message: { _ in Text("This restores the batch to its previous quantity, location and package date.") }
    }
}
