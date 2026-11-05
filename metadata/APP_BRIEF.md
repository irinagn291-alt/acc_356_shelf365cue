<!-- gf-brief source=a47d183f08cbe53591065f04543b61252fe79c80afc644c70963e5a10b0cb1a3 written=2026-11-05T17:55:56+03:00 -->
# Shelf365Cue

## What it is

Shelf365Cue is a pantry inventory app for people who want to keep track of food packages at home. It records batches, package dates, quantities and locations, and provides a diary, calendar and summaries of pantry activity.

## Launch and onboarding

1. A progress indicator appears while the app starts.
2. The native interface opens on “My shelves”, with the “Shelves” tab selected. There is no native onboarding sequence.
3. On an empty shelf, “Pantry overview” shows “0” and “packs on hand”, followed by “Start with a pack from your kitchen”. The page offers “Find a product” and explains:

   > “How your shelves work”  
   > “1. Find or scan a product and save a batch.  
   > 2. Open its ticket to mark packs used or discarded.  
   > 3. Run a stocktake to compare saved quantities with your kitchen.”

   “Start stocktake” is disabled, with “Add your first batch to start a stocktake.” The first-use section says “First delivery”, “What's on your shelf?” and “Search by name or barcode. Add the number of packs, where you keep them and the date on the label.”

The app can also be directed to remotely supplied content at launch, so the native screen is not guaranteed on every installation. The content and its labels cannot be established from the native interface.

## Screens

The four main navigation controls are “Shelves”, “Diary”, “Calendar” and “Insights”. Each opens its corresponding screen. “Contact Us” appears on each main screen and opens the contact page; “Done” closes it.

### My shelves

“Pantry overview” shows the number of packs on hand and a summary of approaching or missing package dates. “Find a product” opens “Food catalog”. “Start stocktake” opens “Stocktake” after at least one batch has been saved.

Once batches exist, “Batches” lists their product, location, quantity and date status. Tapping a batch opens its “Batch ticket”. The controls are:

- “All batches”, “Check soon” and “Undated” filter by date. “Check soon” includes past dates and dates within the next three days.
- “All locations” opens a location filter with “All locations”, “Cupboard”, “Fridge” and “Freezer”.
- “By date”, “By name” and “By quantity” select the sort order.
- “Clear filters” resets the location and date filters when there are no matching batches.

### Food catalog and Barcode

“Food catalog” has a “Name, brand or barcode” field, “Clear”, “Search online” and “Scan”. Search results and “Available offline” products can be selected to start a “New batch”. “Close” returns to the shelves. While an online product’s full label is being opened, the app shows “Opening the full label…”.

The catalog identifies its source as “Open Food Facts” and includes “Open Food Facts · community data”, “Database license · ODbL” and “Photo license · CC BY-SA” links. It says “Starter products and labels you open are stored on this device.” and “Recipes can change. Check the printed package for current ingredients.”

“Scan” opens “Barcode”. On a supported device it requests camera access and scans a package barcode. If scanning is unavailable, “Barcode digits” and “Look up barcode” allow manual entry; “Open Settings” appears when camera access was denied. “Close” returns to the catalog.

If the complete label cannot be retrieved, “Full label unavailable” offers “Use available information” to proceed or “Cancel” to return.

### New batch and Edit batch

The editor displays the chosen product and has:

- “Packs” to change the package count.
- “Location” with “Cupboard”, “Fridge” and “Freezer”.
- “Record the package date” to enable or omit “Package date”.
- “Note”, with the placeholder “e.g. The open pack is at the front”.
- “Stock this batch” to save a new batch, or “Save changes” to save an existing one.
- “Cancel” to close without saving.

The date guidance says “Use the date printed on the package. Leave it off for undated goods.”

### Batch ticket

“Batch ticket” shows the product, packs in stock, location, package date and batch activity. “Edit” opens “Edit batch”. The “Packs” stepper selects how many packages to act on; “Mark used” records them as used, and “Discard” asks for confirmation before recording them as discarded. The confirmation offers “Discard” and “Cancel” and says “This will be recorded in your diary.”

“Product label” expands the barcode and available ingredient information. “View on Open Food Facts ↗” opens the product’s source page when available. If ingredients are missing, it says “Ingredient details are missing from this catalog entry.”

### Stocktake and Stocktake result

“Stocktake” asks “Count the packs you actually have” and explains: “Check each batch in your kitchen. Enter the actual count, or tap Matches. Enter 0 for an empty batch. Nothing changes until you save.”

For every batch, “Matches” fills in the recorded quantity; “Actual pack count” accepts a manually counted quantity. “Save stocktake” saves all counts and opens “Stocktake result”. “Cancel” closes the stocktake, and the keyboard’s “Done” dismisses the keyboard.

The result shows “Stocktake saved”, “Batches checked”, “Total correction” and the recorded and counted quantities for each batch. “Done” closes the result. Corrections appear as “Counted” movements in “Diary”.

### Diary

“Diary” says “Your pantry, day by day” and “Stock movements and barcode lookups are recorded automatically. Add your own notes about products, meals or shopping.”

- “Add a note” opens “Diary note”.
- “Activity”, “Scans” and “Notes” switch between movements and recent stocktakes, barcode lookups, and saved notes.
- In “Activity”, the activity filter offers “All”, “Stocked”, “Used”, “Discarded”, “Adjusted” and “Counted”. Eligible latest movements have “Undo”; its confirmation offers “Undo movement” and “Keep entry”.
- A stocktake entry opens “Stocktake result”. Tapping a note opens it for editing.

“Diary note” contains “Date”, “Product (optional)”, “General note” and “Your note”, with the placeholder “What would you like to remember?”. “Save” saves the note, “Cancel” closes it, and keyboard “Done” dismisses the keyboard. Existing notes also offer “Delete note”, followed by a confirmation titled “Delete this diary note?”.

### Calendar

“Calendar” shows a month grid with “Package date”, “Scan” and “Diary” markers. “Previous month” and “Next month” change the month; selecting a day shows its recorded events. “Today” returns to the current day. “Add note for this day” opens a dated “Diary note”.

The selected day can show “Package dates”, “Barcode lookups”, “Stock movements”, stocktakes and notes. A batch opens its “Batch ticket”; a stocktake opens “Stocktake result”; a note opens for editing. The calendar says “Dates belong to batches still on your shelves. Always check the package before using a product.”

### Insights

“Insights” shows “Your stock, in numbers”, including “Packs on hand now”, “Packs stocked”, “Packs used”, “Packs discarded” and “Barcode lookups”. “7 days”, “30 days”, “90 days” and “All time” change the reporting period.

“Used & discarded” shows a daily chart when there are relevant movements. “Current storage” shows pack counts for “Cupboard”, “Fridge” and “Freezer”. The screen also reports matched barcode lookups, stocktakes and quantity corrections. Counts represent packages rather than servings; undone movements are excluded from reports.

## Features

- Find products by name, brand or barcode, or scan a food package.
- Use starter products and previously opened labels offline.
- Stock batches with pack count, location, package date and note.
- Filter and sort “Batches”.
- Edit a “Batch ticket” and mark packs “Used” or “Discarded”.
- Perform a “Stocktake” and save corrections as “Counted” movements.
- Review and undo eligible stock movements in “Diary”.
- Record dated notes, optionally linked to a product.
- Review package dates, barcode lookups and diary activity in “Calendar”.
- View pantry counts, trends and storage totals in “Insights”.
- Open the product’s available ingredients and source information.
- Open “Contact Us”.
- Use a home-screen widget that opens the shelves.

## Behaviours that can look like bugs

- “Start stocktake” is disabled until a batch exists. Use “Find a product” and “Stock this batch” first.
- “Search online” is disabled until the search field contains input and while a search is running. Enter a name, brand or barcode and wait for any current search.
- “Look up barcode” is disabled until “Barcode digits” contains 4–14 digits. Enter the digits from the package.
- Scanning or searching a barcode does not add stock. Select the product and save it with “Stock this batch”.
- “Save stocktake” is disabled until every listed batch has a valid actual count. Enter a count or tap “Matches” for each one; use 0 for an empty batch.
- “Save” in “Diary note” is disabled for blank notes or notes longer than 2,000 characters. Enter a nonblank note within that limit.
- “No matching batches” says “Try another location or date filter.” Choose another filter or tap “Clear filters”.
- “No movements yet” says “Stock a batch to start your diary. Using and discarding packs creates new entries.” A selected activity filter can also have no entries; choose “All” or record that activity.
- “No barcode lookups yet” says “Open Find a product, then scan a package or search its barcode. Both are saved here.”
- “A fresh page” says “Keep a dated note and optionally link it to a product.” Use “Add a note”.
- “Nothing recorded” says “Package dates, stock movements, scans and notes appear on their recorded day.” Select another day or add activity.
- An empty “Used & discarded” chart says “Mark packs as used or discarded from a batch ticket to see your daily trend.”
- A removed batch can show “This batch is off the shelf” and “Open Diary to see its movements.” “Back to shelves” returns to the list.
- If a batch cannot be saved, “Couldn’t save this batch” says “Check available storage. If the batch changed elsewhere, reopen its ticket and try again.” “Close” dismisses the alert.

## Starter content and resume

The catalog includes starter products available offline; labels opened by the user are also available on the device. The pantry itself starts empty.

Saved batches, diary entries, scans and stocktakes can be revisited. An unfinished batch, note or stocktake is not presented as a resumable draft after closing its editor.

## Permissions

Camera access is requested when “Scan” is opened on a supported device. The usage description is: “Scan a food package barcode to find its product in Open Food Facts.”

## Absent

The native interface has no login or accounts, in-app purchase, ads, analytics controls, account deletion flow or App Tracking Transparency prompt. Users can create content in the form of batches and diary notes.

## Data and support

Pantry records and saved catalog information are kept on the device. Online product searches and barcode lookups contact the product catalog. “Contact Us” opens the support page, and “Done” closes it.

## Scanning and health

The scanner is intended for food-package barcodes; the manual fallback accepts 4–14 barcode digits. The native flow does not offer QR-code scanning as a feature.

The app displays available product ingredients under “Product label”. It does not present medical advice or a product-health assessment. The catalog provides the “Open Food Facts · community data” source link and license links, and product tickets can link to the corresponding Open Food Facts page.

## Platform

The native interface uses English and US-style locale formatting; the calendar starts on Monday. It supports iPhone and iPad and requires iOS 17.0 or later. iPhone supports portrait and both landscape orientations; iPad also supports upside-down portrait.

## Category

Food & Drink.
