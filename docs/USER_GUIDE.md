# JTM iOS App User Guide

JTM keeps your railway journeys on a live map and turns the same records into a searchable log, statistics, and playback. This guide starts with the shortest path to a useful map, then covers the tasks you are most likely to repeat.

## Contents

- [Before you start](#before-you-start)
- [Understand the workspace](#understand-the-workspace)
- [Create your first journey](#create-your-first-journey)
- [Find and manage journeys](#find-and-manage-journeys)
- [Import journey data](#import-journey-data)
- [Import a route screenshot](#import-a-route-screenshot)
- [Export and recover your data](#export-and-recover-your-data)
- [Use the map](#use-the-map)
- [Read statistics](#read-statistics)
- [Play and export a journey](#play-and-export-a-journey)
- [Change language and display settings](#change-language-and-display-settings)
- [Troubleshooting](#troubleshooting)
- [Privacy and storage](#privacy-and-storage)

## Before you start

You need an iPhone or iPad running iOS 17 or later. Apple Maps needs network access to load its basemap, but your saved journeys, bundled railway data, JSON import and export, route calculation, and statistics are local to the device.

On first launch, the app begins loading all five bundled railway networks:

- Japan
- Taiwan
- Hong Kong
- Macao
- Korea

You can browse existing journey records while a network loads. Route drawing and station matching for a region become available after that region's package is ready.

## Understand the workspace

The map is always the background. A panel sits over or beside it, depending on the window shape.

The four bottom destinations answer different questions:

| Destination | What it shows |
| --- | --- |
| **Upcoming** | Journeys dated today or later, soonest first |
| **Stats** | Mileage, coverage, travel time, service mix, and frequently ridden sections |
| **All** | Every recorded journey grouped by date |
| **Search** | Journey search and the entry point for adding a journey |

Drag the panel between compact, medium, and expanded heights on standard text sizes. At accessibility text sizes, the app offers compact and expanded heights so content is not trapped in a half-height panel.

Use the gear-shaped utility menu in the panel header to open these temporary tasks:

- **Data Library** manages imports, exports, samples, backups, and deletion.
- **Settings** changes language, map appearance, labels, route display, and diagnostics.

Closing either task returns you to the same destination and scroll position.

## Create your first journey

Create a journey when you want full control over its date, service, stops, and route rules.

1. Open **Search**.
2. Choose **New journey**.
3. Enter the journey date and identifying information.
4. Add at least the origin and destination stops.
5. Add intermediate stops when they affect the route or the record you want to keep.
6. Mark each stop appropriately, including whether the adjacent segment was ridden.
7. Review any validation messages shown beside a field.
8. Choose **Save**.

The app saves the record locally, resolves its route, and refreshes the map. A route that cannot be solved affects only that journey; the rest of the library remains available.

### Edit an existing journey

Open a journey from **Upcoming**, **All**, or **Search**, then choose **Edit**. Saving replaces the complete journey record and refreshes its route, playback, and statistics.

The journey action menu also supports common record operations:

- Duplicate a journey.
- Move it earlier or later within its group.
- Hide or show it on the map.
- Delete it.
- Rebuild its route from the current stops.

## Find and manage journeys

Use **Search** to match journey names, train information, stations, and other indexed fields. Clear the query to return to the unfiltered list.

Use the date filter from the utility menu when you want the list and map to focus on one day. The app can also dim off-date rides or make the map follow the selected date, depending on your settings.

Journeys that cross midnight retain their day boundaries. Settings can either show the complete run or draw the portion belonging to another calendar day with a dashed treatment.

## Import journey data

JTM accepts its canonical JSON store, a JSON array of trains, or a single train object. Import always includes a preflight step before the working library changes.

1. Open the utility menu.
2. Choose **Data Library**.
3. Choose **Import**.
4. Select **Open JSON** or **Paste JSON text**.
5. Choose an import mode:
   - **Append** keeps current journeys and adds incoming records. A colliding incoming ID receives a new ID.
   - **Replace all** removes the current working set and replaces it with the imported records.
6. Review the detected region, journey count, renamed IDs, and validation issues.
7. Start the import only when the preview matches your intent.

The app writes a recovery backup before destructive replacement. Cancelling during preflight leaves the current library unchanged.

### Load bundled samples

The Data Library contains seven bundled samples grouped by region. A normal tap folds the sample into your working set. A long press offers to replace the complete working set with that sample.

Editing a sample creates your own saved data. The bundled sample itself is never overwritten.

## Import a route screenshot

The screenshot importer reads supported Japanese route-planner images with Vision OCR. Because OCR can misread a digit or station name, nothing is saved until you review the parsed journey.

1. Wait until the Japanese network has finished loading.
2. Open **Data Library**.
3. In the Import section, choose the route screenshot option.
4. Select up to eight images from Photos, or choose image files.
5. Review the date, status, parsed legs, station matches, times, platforms, fares, and line names.
6. Choose whether the trip happened or is only planned.
7. Select which parsed trains to keep.
8. Commit the import.

Use the regular journey editor after import to correct any detail that OCR did not read accurately.

## Export and recover your data

Use **Data Library** for every data-ownership task.

### Export JSON

1. Open **Data Library**.
2. Find **Export and backup**.
3. Choose **Export JSON** to save a document, or copy the JSON when you need to paste it elsewhere.
4. Store the exported file somewhere you control.

The export uses the same canonical spelling as the web implementation, including `schema_version` and the `trains` array.

### Recover from a destructive operation

The app keeps one recovery backup before import replacement, replacement edits, or deleting all journeys.

1. Open **Data Library**.
2. Find the recovery backup card.
3. Confirm its creation date, reason, and journey count.
4. Choose **Restore backup**.

Restoring consumes the backup and replaces the active store. Export important data before restoring when you need to preserve both versions.

### Delete data

The folded **Danger zone** contains two distinct operations:

- **Delete saved rides** removes the saved on-device store, then reloads the remaining available source.
- **Delete all** empties the current journey set and saves the empty result.

Read the confirmation message carefully. The app creates a recovery backup before these operations when a store is available.

## Use the map

Map controls stay on the right side of the map. They control the map itself rather than the open panel.

Use them to:

- Frame the loaded railway network or the current selection.
- Move to your device location after granting location permission.
- Zoom in or out.
- Reset the compass.
- Open map-layer controls.
- Open map information and data-source licenses.

Tap a station to open its names, readings, operator badges, and Apple Maps place. When Apple Maps can resolve a real station place, the app opens that place; otherwise it opens a labeled coordinate pin.

Tap a ridden route to select its journey. When several rides cross under the same point, the app lists the candidates so you can choose the intended one.

### Change visible layers

The map-layer screen can independently show or hide:

- Railway routes
- Stations
- Terminals
- Pass markers
- Ridden-route categories

Turning off a ridden category may take a moment the first time because the app builds the regional classification index on demand.

## Read statistics

Open **Stats** to review the selected date and region scope. Choose one region when you want its category rules and network denominator, or choose **All regions** for the merged network.

The statistics workspace includes:

- Journey, travel-day, stop, and ride-time totals
- High-speed, limited-express, and other service groups
- Mileage by category
- Network coverage
- Per-line details
- Most frequently ridden sections
- Selected-day distance and time

Selecting a region frames that region's complete network on the map. Selecting all regions frames the combined coverage area.

## Play and export a journey

Open a journey and choose its playback action. The shared transport remains active when you switch between primary destinations.

Playback provides:

- Previous and next journey controls
- Pause, resume, and stop
- Speed control
- Optional focus zoom
- Completed-route trails
- A closing overview after the last journey

To export a video, open the video options before starting the run. Choose the frame shape, quality, and bitrate, then start the export. A cancelled export finishes the partial movie it has already encoded rather than discarding every completed frame.

## Change language and display settings

Open the utility menu and choose **Settings**.

The interface supports:

- Traditional Chinese
- Simplified Chinese
- Japanese
- English

Settings also control station readings, light or dark appearance, basemap opacity, railway and station styling, selection emphasis, off-date dimming, and cross-day display.

The Diagnostics section reports each regional package separately. A failed package is not hidden behind the line counts of packages that loaded successfully.

Resetting display settings does not change journeys or exported JSON.

## Troubleshooting

### The basemap is blank on first simulator launch

MapKit can time out while initializing tiles on a fresh simulator. Quit and relaunch the app once. Your bundled railway and journey data are not deleted.

### One region has no railways

Open **Settings**, then check **Diagnostics**. If that region reports a package failure, retry the network load from the Data Library. Journey records can still be browsed, edited, imported, and exported while the regional network is unavailable.

### A saved route is not drawn

Open the journey and review its route status. Confirm that the journey has a region, resolvable origin and destination stops, and valid adjacent route sections. Use **Rebuild route** after correcting the stops.

### JSON cannot be imported

Read every preflight issue and its JSON path. The importer accepts a complete store, a train array, or one train object, but every journey must still pass the current validation rules. Current journeys remain unchanged until preflight succeeds and the import commits.

### A screenshot produces the wrong station or time

Return to the screenshot preview and compare every leg with the source image. OCR is intentionally review-first. Import the useful legs, then correct the saved journey in the editor.

### Changes disappeared after relaunch

Open **Data Library** and look for a save error. Records can remain in memory after a failed save, but relaunch restores the last version that reached disk. Choose **Save again**, then export JSON as an additional backup.

### Apple Maps opens a pin instead of a station place

The place lookup did not find a confident match. The fallback pin preserves the station name and coordinate, but it may not include Apple Maps platform or exit metadata.

## Privacy and storage

Journey data is stored as canonical JSON under the app's Application Support directory. Writes are serialized and atomic, and that directory is excluded from iCloud backup because it is application state rather than a user-created document.

The app requests location access only to show your position on the railway map. Screenshot import processes selected images with Apple's Vision framework. Exported JSON and videos leave the app only when you choose a destination through the system share or document interface.

For developer-facing details, see the [RailKit API reference](API_REFERENCE.md). For build and recovery procedures, see the [runbook](RUNBOOK.md).
