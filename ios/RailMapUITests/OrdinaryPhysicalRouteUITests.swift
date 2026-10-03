import XCTest

@MainActor
final class OrdinaryPhysicalRouteUITests: XCTestCase {
    func testGuidedCorrectionPreviewsBeforeApplyingAndCanUndo() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = "new"
        app.launch()
        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorTrainType"].firstMatch.exists)
        next.tap()
        for (index, station, code) in [(0, "東京", "003766"), (1, "品川", "004095")] {
            let row = app.descendants(matching: .any)["rideEditorStop-\(index)"].firstMatch
            EditorUITestSupport.tap(row, in: app)
            let input = app.otherElements["rideEditorStopName"].textFields.firstMatch
            XCTAssertTrue(input.waitForExistence(timeout: 8))
            input.tap()
            input.typeText(station)
            let suggestion = app.buttons["rideEditorStationSuggestion-\(code)"]
            XCTAssertTrue(suggestion.waitForExistence(timeout: 8))
            suggestion.tap()
            app.navigationBars.buttons.firstMatch.tap()
        }
        openRouteGuide(in: app)
        comparePaths(in: app)
        confirmChoices(preferring: "東海道線", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["routeGuideChangeSummary"].firstMatch.exists)
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "Guided railway route review"
        preview.lifetime = .keepAlways
        add(preview)
        app.buttons["routeGuideApply"].tap()
        let lastSurfaceStop = app.descendants(matching: .any)["rideEditorStop-6"].firstMatch
        revealSurfaceDestination(lastSurfaceStop, in: app)
        XCTAssertTrue(lastSurfaceStop.waitForExistence(timeout: 8), "The physical surface route adds all five intermediate stations.")

        // A delete gesture opens a replacement proposal without changing the record.
        deleteRow(1, in: app)
        XCTAssertTrue(app.buttons["routeCorrectionCompare"].waitForExistence(timeout: 10))
        app.buttons["routeCorrectionCancel"].tap()
        XCTAssertTrue(app.buttons["routeCorrectionCancel"].waitForNonExistence(timeout: 8))
        let canceledVisit = app.descendants(matching: .any)["rideEditorStop-1"].firstMatch
        revealEditorStop(canceledVisit, in: app)
        recordFailure("after-initial-delete-cancel-visit-preservation", app: app)
        XCTAssertTrue(canceledVisit.waitForExistence(timeout: 8),
                      "Cancelling the delete proposal must restore the original second visit's row.")
        XCTAssertTrue(canceledVisit.label.hasPrefix("2, 有楽町,"),
                      "Cancelling must retain Yurakucho at the original visit ordinal.")
        revealSurfaceDestination(lastSurfaceStop, in: app)
        XCTAssertTrue(lastSurfaceStop.waitForExistence(timeout: 8), "Cancelling must keep every original visit.")

        deleteRow(1, in: app)
        comparePaths(in: app)
        confirmChoices(preferring: "総武線", in: app)
        app.buttons["routeGuideApply"].tap()
        let intermediate = app.descendants(matching: .any)["rideEditorStop-1"].firstMatch
        revealEditorStop(intermediate, in: app)
        XCTAssertTrue(intermediate.waitForExistence(timeout: 8))
        XCTAssertTrue(intermediate.label.contains("新橋"))
        XCTAssertFalse(app.descendants(matching: .any)["rideEditorStop-3"].firstMatch.exists)

        // No verified alternative leaves the current tunnel route intact.
        deleteRow(1, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["routeCorrectionEmpty"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["routeCorrectionCompare"].isEnabled)
        app.buttons["routeCorrectionCancel"].tap()
        revealEditorStop(intermediate, in: app)
        XCTAssertTrue(intermediate.waitForExistence(timeout: 8))
        XCTAssertTrue(intermediate.label.contains("新橋"))
        let undo = app.buttons["rideEditorUndoRoute"]
        EditorUITestSupport.tap(undo, in: app)
        revealSurfaceDestination(lastSurfaceStop, in: app)
        XCTAssertTrue(lastSurfaceStop.waitForExistence(timeout: 8), "Undo restores the prior path and its stations together.")

        // Editing an automatic visit protects it from silent route replacement.
        EditorUITestSupport.tap(app.descendants(matching: .any)["rideEditorStop-1"].firstMatch, in: app)
        let platform = app.otherElements["rideEditorStopPlatform"].textFields.firstMatch
        XCTAssertTrue(platform.waitForExistence(timeout: 8))
        platform.tap()
        platform.typeText("3")
        app.navigationBars.buttons.firstMatch.tap()
        openRouteGuide(in: app)
        comparePaths(in: app)
        confirmChoices(preferring: "総武線", in: app)
        app.buttons["routeGuideApply"].tap()
        let remove = app.buttons["Remove stations and apply route"]
        XCTAssertTrue(remove.waitForExistence(timeout: 8), "Recorded station details require explicit approval.")
        // iOS presents the cancel role as the native popover's outside-dismiss surface.
        let popover = app.popovers.firstMatch
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        XCTAssertTrue(popover.waitForExistence(timeout: 5))
        XCTAssertTrue(dismissRegion.waitForExistence(timeout: 5))
        XCTAssertTrue(dismissRegion.isHittable)
        let dismissCenter = CGPoint(x: dismissRegion.frame.midX, y: dismissRegion.frame.midY)
        XCTAssertFalse(popover.frame.contains(dismissCenter),
                       "The observed native dismiss target must be outside the destructive popover.")
        recordFailure("protected-removal-popover-before-native-cancel", app: app)
        dismissRegion.tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 8))
        XCTAssertTrue(popover.waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.buttons["routeGuideApply"].waitForExistence(timeout: 8))

        // Inspect the retained draft after cancelling, before proposing replacement again.
        app.buttons["routeGuideCancel"].tap()
        XCTAssertTrue(app.buttons["routeGuideApply"].waitForNonExistence(timeout: 8))
        let protectedVisit = app.descendants(matching: .any)["rideEditorStop-1"].firstMatch
        revealEditorStop(protectedVisit, in: app)
        XCTAssertTrue(protectedVisit.label.hasPrefix("2, 有楽町,"),
                      "Cancelling protected replacement must retain the same visit ordinal and name.")
        XCTAssertTrue(protectedVisit.label.contains("Platform 3"),
                      "Cancelling must retain the protected authored platform exactly.")
        revealSurfaceDestination(lastSurfaceStop, in: app)
        recordFailure("protected-removal-cancel-keeps-surface-route-and-platform", app: app)
        openRouteGuide(in: app)
        comparePaths(in: app)
        confirmChoices(preferring: "総武線", in: app)
        app.buttons["routeGuideApply"].tap()
        XCTAssertTrue(remove.waitForExistence(timeout: 8))
        remove.tap()
        revealEditorStop(intermediate, in: app)
        XCTAssertTrue(intermediate.waitForExistence(timeout: 8))
        XCTAssertTrue(intermediate.label.contains("新橋"))
        XCTAssertFalse(app.descendants(matching: .any)["rideEditorStop-3"].firstMatch.exists)
        saveAndReopenTunnel(in: app)
    }

    /// Save the final protected-stop-approved tunnel through the normal wizard.
    private func saveAndReopenTunnel(in app: XCUIApplication) {
        let number = "RoutePersist-\(UUID().uuidString.prefix(8))"
        let editor = app.descendants(matching: .any)["rideEditorForm"].firstMatch
        let expectedNames = ["東京", "新橋", "品川"]
        var visitLabels: [String] = []
        for (index, name) in expectedNames.enumerated() {
            let stop = app.descendants(matching: .any)["rideEditorStop-\(index)"].firstMatch
            revealEditorStop(stop, in: app)
            XCTAssertTrue(stop.label.hasPrefix("\(index + 1), \(name),"))
            visitLabels.append(stop.label)
        }
        XCTAssertFalse(app.descendants(matching: .any)["rideEditorStop-3"].firstMatch.exists)

        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.isEnabled)
        next.tap()
        let numberField = app.otherElements["rideEditorNumber"].textFields.firstMatch
        XCTAssertTrue(numberField.waitForExistence(timeout: 8))
        EditorUITestSupport.tap(numberField, in: app)
        numberField.typeText(number + "\n")
        XCTAssertEqual(numberField.value as? String, number)
        let tunnelService = app.buttons["rideEditorServiceLeg-0"]
        XCTAssertTrue(reveal(tunnelService, in: editor, app: app))
        XCTAssertTrue(tunnelService.label.contains("総武線"),
                      "The selected physical tunnel line must be recorded before Save.")
        let serviceLabel = tunnelService.label

        next.tap()
        EditorUITestSupport.enableDate(in: app)
        let dateInput = app.textFields["rideEditorDateInput"]
        XCTAssertTrue(dateInput.waitForExistence(timeout: 8))
        let date = dateInput.value as? String ?? ""
        XCTAssertNotNil(date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression))
        next.tap()
        let save = app.buttons["rideEditorSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        XCTAssertTrue(save.isEnabled, "The normal completion step must permit this complete draft.")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 15))

        app.tabBars.firstMatch.buttons.element(boundBy: 3).tap()
        let search = app.textFields["journeySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        EditorUITestSupport.tap(search, in: app)
        let oldQuery = search.value as? String ?? ""
        if !oldQuery.isEmpty && oldQuery != search.placeholderValue {
            let clear = app.buttons["Clear search"]
            XCTAssertTrue(clear.waitForExistence(timeout: 5))
            clear.tap()
        }
        search.typeText(number)
        XCTAssertEqual(search.value as? String, number)
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                    "journeyRow-", number)
        let inserted = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(inserted.waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons.matching(predicate).count, 1,
                       "The UUID-tagged number must identify exactly the newly saved journey.")
        let savedJourneyIdentifier = inserted.identifier
        // Match existing JourneySave coverage's asynchronous storage completion window.
        Thread.sleep(forTimeInterval: 1)
        app.terminate()
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = ""
        app.launchEnvironment.removeValue(forKey: "RAILMAP_UI_TEST_SAMPLE")
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "search"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = number
        app.launch()
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        XCTAssertEqual(search.value as? String, number)
        let persisted = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(persisted.waitForExistence(timeout: 30), "The same journey must reload from disk.")
        XCTAssertEqual(app.buttons.matching(predicate).count, 1)
        XCTAssertEqual(persisted.identifier, savedJourneyIdentifier)
        persisted.press(forDuration: 1)
        let information = app.buttons["Journey information"]
        XCTAssertTrue(information.waitForExistence(timeout: 8))
        information.tap()
        let edit = app.buttons["journeyMenuEdit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        for (index, name) in expectedNames.enumerated() {
            let stop = app.descendants(matching: .any)["rideEditorStop-\(index)"].firstMatch
            revealEditorStop(stop, in: app)
            XCTAssertTrue(stop.label.hasPrefix("\(index + 1), \(name),"))
            XCTAssertEqual(stop.label, visitLabels[index],
                           "Save/reopen must preserve the ordered visit and its displayed details.")
        }
        XCTAssertFalse(app.descendants(matching: .any)["rideEditorStop-3"].firstMatch.exists)
        XCTAssertTrue(reveal(tunnelService, in: editor, app: app))
        XCTAssertEqual(tunnelService.label, serviceLabel,
                       "The physical tunnel's endpoint/operator/line summary must survive persistence.")
        XCTAssertTrue(revealEarlierSavedField(numberField, in: app))
        XCTAssertEqual(numberField.value as? String, number)
        XCTAssertTrue(revealEarlierSavedField(dateInput, in: app))
        XCTAssertEqual(dateInput.value as? String, date)
        recordFailure("repaired-tunnel-route-after-save-and-relaunch", app: app)
        let evidence = XCTAttachment(string:
            "Saved journey AX identifier=\(savedJourneyIdentifier); unique number=\(number); "
            + "expected raw station names=\(expectedNames); expected stop count=3; "
            + "date=\(date); physical service summary=\(serviceLabel). "
            + "UI checks prove saved journey identity, ordered names/details and visible line metadata. "
            + "Raw visit UUIDs, station codes, line_ids and section_codes need read-only persisted JSON inspection.")
        evidence.name = "repaired-route-persisted-record-identity-and-evidence-limits"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    /// Reopened number/date belong to Basics, before the stop and service sections.
    private func revealEarlierSavedField(_ field: XCUIElement, in app: XCUIApplication) -> Bool {
        let form = app.collectionViews["rideEditorForm"].firstMatch
        guard form.waitForExistence(timeout: 5) else { return false }
        for attempt in 0...4 {
            let bounds = usableBounds(of: form, in: app)
            if field.exists && field.isHittable && bounds.contains(field.frame) { return true }
            guard attempt < 4, bounds.height > 40 else { return false }
            let controls = form.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH %@", "rideEditor")).allElementsBoundByIndex
                .filter { $0.exists && $0.isHittable && bounds.contains($0.frame) }
                .sorted { $0.frame.minY < $1.frame.minY }
            var anchorID: String?
            var nativeCell: XCUIElement?
            for control in controls {
                let identifier = control.identifier
                let cell = form.cells.containing(.any, identifier: identifier).firstMatch
                if cell.exists && cell.isHittable && bounds.contains(cell.frame) {
                    anchorID = identifier
                    nativeCell = cell
                    break
                }
            }
            guard let anchorID, let nativeCell else { return false }
            let anchor = app.descendants(matching: .any)[anchorID].firstMatch
            let beforeAnchor = anchor.frame
            let beforeForm = form.frame
            let startPoint = CGPoint(x: nativeCell.frame.midX, y: nativeCell.frame.midY)
            let endPoint = CGPoint(x: startPoint.x,
                                  y: min(bounds.maxY - 2, startPoint.y + bounds.height * 0.4))
            guard endPoint.y - startPoint.y > 10 else { return false }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: startPoint.x - app.frame.minX,
                                      dy: startPoint.y - app.frame.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(
                    dx: endPoint.x - app.frame.minX, dy: endPoint.y - app.frame.minY)))
            let afterForm = form.frame
            let fieldRevealed = field.exists && field.isHittable
                && usableBounds(of: form, in: app).contains(field.frame)
            let anchorMovedDown = anchor.exists && anchor.frame.minY > beforeAnchor.minY + 1
            let formStayed = abs(afterForm.minY - beforeForm.minY) < 2
                && abs(afterForm.height - beforeForm.height) < 2
            let evidence = XCTAttachment(string:
                "Saved Basics field return toward earlier rows \(attempt + 1): "
                + "anchor=\(anchorID), beforeAnchor=\(beforeAnchor), "
                + "anchorMovedDown=\(anchorMovedDown), fieldRevealed=\(fieldRevealed), "
                + "Form before=\(beforeForm), after=\(afterForm), formStayed=\(formStayed).")
            evidence.name = "saved-route-basics-native-content-progress-\(attempt + 1)"
            evidence.lifetime = .keepAlways
            add(evidence)
            guard formStayed && (fieldRevealed || anchorMovedDown) else { return false }
        }
        return false
    }

    private func revealEditorStop(_ stop: XCUIElement, in app: XCUIApplication) {
        let form = app.descendants(matching: .any)["rideEditorForm"].firstMatch
        XCTAssertTrue(reveal(stop, in: form, app: app),
                      "The requested indexed stop must materialize inside usable Form content.")
    }

    private func revealSurfaceDestination(_ stop: XCUIElement, in app: XCUIApplication) {
        revealEditorStop(stop, in: app)
        XCTAssertTrue(stop.label.hasPrefix("7, 品川,"),
                      "The five-intermediate surface route must end at visit 7, Shinagawa.")
    }

    private func openRouteGuide(in app: XCUIApplication) {
        let lines = app.buttons["rideEditorLines"]
        guard revealRouteEntry(lines, in: app) else {
            recordFailure("route-guide-entry-outside-form", app: app)
            XCTFail("Route guide entry must be inside usable Form content before tapping.")
            return
        }
        XCTAssertTrue(lines.isEnabled, app.debugDescription)
        lines.tap()
        let destination = app.navigationBars["Choose the railway route"]
        guard destination.waitForExistence(timeout: 10),
              app.buttons["routeCorrectionCancel"].exists,
              app.descendants(matching: .any)["routeCorrectionFrom"].firstMatch.exists else {
            recordFailure("route-correction-destination-missing", app: app)
            XCTFail("The entry must open the current route-correction destination, not advance the editor.")
            return
        }
    }

    /// The route-guide row precedes stops; a missing lazy row is above this section.
    private func revealRouteEntry(_ entry: XCUIElement, in app: XCUIApplication) -> Bool {
        let form = app.collectionViews["rideEditorForm"].firstMatch
        guard form.waitForExistence(timeout: 5) else { return false }
        func visibleStops() -> [XCUIElement] {
            let bounds = usableBounds(of: form, in: app)
            return form.buttons.allElementsBoundByIndex.filter {
                $0.identifier.hasPrefix("rideEditorStop-") && $0.exists
                    && $0.isHittable && bounds.contains($0.frame)
            }.sorted { $0.frame.minY < $1.frame.minY }
        }
        for attempt in 0...4 {
            let bounds = usableBounds(of: form, in: app)
            if entry.exists && entry.isHittable && bounds.contains(entry.frame) { return true }
            guard attempt < 4, bounds.height > 40, let candidate = visibleStops().first else {
                return false
            }
            // Resolve by stable accessibility identifier, not a changing query index.
            let anchor = app.buttons[candidate.identifier]
            let cell = form.cells.containing(.button, identifier: candidate.identifier).firstMatch
            guard cell.exists && cell.isHittable && bounds.contains(cell.frame) else { return false }
            let beforeForm = form.frame
            let beforeAnchor = anchor.frame
            let beforeIndex = Int(candidate.identifier.dropFirst("rideEditorStop-".count))
            let startPoint = CGPoint(x: cell.frame.midX, y: cell.frame.midY)
            let endPoint = CGPoint(x: startPoint.x,
                                  y: min(bounds.maxY - 2, startPoint.y + bounds.height * 0.4))
            guard endPoint.y - startPoint.y > 10 else { return false }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: startPoint.x - app.frame.minX,
                                      dy: startPoint.y - app.frame.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(
                    dx: endPoint.x - app.frame.minX, dy: endPoint.y - app.frame.minY)))
            let afterForm = form.frame
            let afterBounds = usableBounds(of: form, in: app)
            let entryRevealed = entry.exists && entry.isHittable && afterBounds.contains(entry.frame)
            let anchorMovedDown = anchor.exists && anchor.frame.minY > beforeAnchor.minY + 1
            let afterIndex = visibleStops().first.flatMap {
                Int($0.identifier.dropFirst("rideEditorStop-".count))
            }
            let earlierVisitAppeared = beforeIndex != nil && afterIndex != nil
                && afterIndex! < beforeIndex!
            let formStayed = abs(afterForm.minY - beforeForm.minY) < 2
                && abs(afterForm.height - beforeForm.height) < 2
            let evidence = XCTAttachment(string:
                "Route guide is above stops. Native downward content drag \(attempt + 1): "
                + "Form before=\(beforeForm), after=\(afterForm), anchor=\(candidate.identifier), "
                + "beforeAnchor=\(beforeAnchor), anchorMovedDown=\(anchorMovedDown), "
                + "beforeVisibleOrdinal=\(String(describing: beforeIndex)), "
                + "afterVisibleOrdinal=\(String(describing: afterIndex)), "
                + "entryRevealed=\(entryRevealed), formStayed=\(formStayed).")
            evidence.name = "route-guide-earlier-row-native-content-progress-\(attempt + 1)"
            evidence.lifetime = .keepAlways
            add(evidence)
            guard formStayed && (entryRevealed || anchorMovedDown || earlierVisitAppeared) else {
                return false
            }
        }
        return false
    }

    private func comparePaths(in app: XCUIApplication) {
        let compare = app.buttons["routeCorrectionCompare"]
        guard compare.waitForExistence(timeout: 15) else {
            recordFailure("route-correction-loading-error-empty", app: app)
            XCTFail("Route comparison control is missing from the foreground correction sheet.")
            return
        }
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: compare)
        waitForExpectations(timeout: 20)
        compare.tap()
        XCTAssertTrue(app.buttons["routeGuideCancel"].waitForExistence(timeout: 10),
                      "Comparison must enter the current guided route preview.")
    }

    private func confirmChoices(preferring line: String, in app: XCUIApplication) {
        let apply = app.buttons["routeGuideApply"]
        for _ in 0..<12 {
            if apply.exists { break }
            let preferred = app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "routeGuideOption", line)).firstMatch
            let fallback = app.buttons["routeGuideOption1"]
            XCTAssertTrue(fallback.waitForExistence(timeout: 10))
            let option = preferred.exists ? preferred : fallback
            let foreground = app.scrollViews.firstMatch
            guard revealGuideOption(option, in: foreground, app: app) else {
                recordFailure("route-guide-option-outside-preview", app: app)
                XCTFail("The chosen option must be visible in the foreground guide ScrollView.")
                return
            }
            option.tap()
            app.buttons["routeGuideConfirm"].tap()
        }
        XCTAssertTrue(apply.waitForExistence(timeout: 10))
        XCTAssertTrue(apply.isEnabled)
    }

    /// Scroll from a real option card; starting inside the Map pans the Map.
    private func revealGuideOption(_ option: XCUIElement, in scroll: XCUIElement,
                                   app: XCUIApplication) -> Bool {
        guard scroll.waitForExistence(timeout: 5) else { return false }
        for attempt in 0...2 {
            let bounds = usableBounds(of: scroll, in: app)
            guard option.exists, bounds.height > 40, option.frame.height <= bounds.height else {
                return false
            }
            let beforeOption = option.frame
            if option.isHittable && bounds.contains(beforeOption) { return true }
            guard attempt < 2 else { return false }
            let up = beforeOption.maxY > bounds.maxY
            guard up || beforeOption.minY < bounds.minY else { return false }
            let cards = scroll.buttons.allElementsBoundByIndex.filter {
                $0.identifier.hasPrefix("routeGuideOption") && $0.exists && $0.isHittable
                    && bounds.contains($0.frame)
            }.sorted { $0.frame.minY < $1.frame.minY }
            guard let card = up ? cards.last : cards.first else { return false }
            let cardID = card.identifier
            let cardFrame = card.frame
            let startPoint = CGPoint(x: cardFrame.midX, y: cardFrame.midY)
            let neededDistance = (up ? beforeOption.maxY - bounds.maxY
                                     : bounds.minY - beforeOption.minY) + 20
            let availableDistance = up ? startPoint.y - bounds.minY - 2
                                       : bounds.maxY - startPoint.y - 2
            let distance = min(neededDistance, availableDistance)
            guard distance > 10 else { return false }
            let endPoint = CGPoint(x: startPoint.x, y: startPoint.y + (up ? -distance : distance))
            let beforeScroll = scroll.frame
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: startPoint.x - app.frame.minX,
                                      dy: startPoint.y - app.frame.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(
                    dx: endPoint.x - app.frame.minX, dy: endPoint.y - app.frame.minY)))
            guard option.exists else { return false }
            let afterScroll = scroll.frame
            let afterOption = option.frame
            let contentMoved = up ? afterOption.minY < beforeOption.minY - 1
                                  : afterOption.minY > beforeOption.minY + 1
            let scrollStayed = abs(afterScroll.minY - beforeScroll.minY) < 2
                && abs(afterScroll.height - beforeScroll.height) < 2
            let evidence = XCTAttachment(string:
                "Guide option content drag \(attempt + 1): actual card=\(cardID), "
                + "cardFrame=\(cardFrame), start=\(startPoint), end=\(endPoint), "
                + "optionBefore=\(beforeOption), optionAfter=\(afterOption), "
                + "ScrollView before=\(beforeScroll), after=\(afterScroll), "
                + "contentMoved=\(contentMoved), scrollStayed=\(scrollStayed).")
            evidence.name = "route-guide-option-card-anchored-content-progress-\(attempt + 1)"
            evidence.lifetime = .keepAlways
            add(evidence)
            guard contentMoved && scrollStayed else { return false }
        }
        return false
    }

    private func usableBounds(of container: XCUIElement, in app: XCUIApplication) -> CGRect {
        var bounds = container.frame.intersection(app.frame)
        for bar in app.navigationBars.allElementsBoundByIndex where bar.exists && bar.frame.intersects(bounds) {
            let top = max(bounds.minY, bar.frame.maxY)
            bounds = CGRect(x: bounds.minX, y: top, width: bounds.width, height: max(0, bounds.maxY - top))
        }
        // The covered editor's Next button is not a guide-sheet boundary.
        let footerIDs = container.identifier == "rideEditorForm"
            ? ["rideEditorNext"] : ["routeGuideConfirm", "routeGuideApply", "routeGuidePrevious"]
        for id in footerIDs {
            let button = app.buttons[id]
            if button.exists && button.frame.intersects(bounds) {
                bounds.size.height = max(0, button.frame.minY - bounds.minY)
            }
        }
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists && keyboard.frame.intersects(bounds) {
            bounds.size.height = max(0, keyboard.frame.minY - bounds.minY)
        }
        return bounds.insetBy(dx: 8, dy: 8)
    }

    private func drag(_ container: XCUIElement, up: Bool, in app: XCUIApplication) -> Bool {
        let bounds = usableBounds(of: container, in: app)
        guard bounds.width > 20, bounds.height > 40 else { return false }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: bounds.midX - app.frame.minX,
            dy: bounds.minY + bounds.height * (up ? 0.7 : 0.3) - app.frame.minY))
        let end = origin.withOffset(CGVector(dx: bounds.midX - app.frame.minX,
            dy: bounds.minY + bounds.height * (up ? 0.3 : 0.7) - app.frame.minY))
        start.press(forDuration: 0.05, thenDragTo: end)
        return true
    }

    private func reveal(_ element: XCUIElement, in container: XCUIElement, app: XCUIApplication) -> Bool {
        guard container.waitForExistence(timeout: 5) else { return false }
        for _ in 0..<14 {
            let bounds = usableBounds(of: container, in: app)
            if element.exists && element.isHittable && bounds.contains(element.frame) { return true }
            let up = !element.exists || element.frame.maxY > bounds.maxY
            guard drag(container, up: up, in: app) else { return false }
        }
        return false
    }

    private func recordFailure(_ name: String, app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + "-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private func deleteRow(_ index: Int, in app: XCUIApplication) {
        let row = app.descendants(matching: .any)["rideEditorStop-\(index)"].firstMatch
        let form = app.collectionViews["rideEditorForm"].firstMatch
        func recordScroll(_ name: String) {
            let cells = form.cells.allElementsBoundByIndex.filter { $0.exists }
            let description = "Form=\(form.frame), usable=\(usableBounds(of: form, in: app)), "
                + "targetExists=\(row.exists), targetFrame=\(row.exists ? row.frame : .zero)\n"
                + cells.map { "\($0.identifier): \($0.frame)" }.joined(separator: "\n")
            let attachment = XCTAttachment(string: description)
            attachment.name = name + "-actual-scroll-geometry"
            attachment.lifetime = .keepAlways
            add(attachment)
            recordFailure(name, app: app)
        }
        let beforeBounds = usableBounds(of: form, in: app)
        if !(row.exists && row.isHittable && beforeBounds.contains(row.frame)) {
            recordScroll("before-delete-\(index)-controlled-reveal")
            let beforeFrame = form.frame
            let visibleCells = form.cells.allElementsBoundByIndex.filter {
                $0.exists && $0.isHittable && beforeBounds.contains($0.frame)
                    && $0.frame.height > 10
            }
            guard let cell = visibleCells.first, beforeBounds.height > 40 else {
                XCTFail("No actual native Form cell can start the return scroll.")
                return
            }
            let startPoint = CGPoint(x: cell.frame.midX, y: cell.frame.midY)
            let endY = min(beforeBounds.maxY - 2, startPoint.y + beforeBounds.height * 0.4)
            guard endY - startPoint.y > 10 else {
                XCTFail("Visible native cell has no downward drag distance.")
                return
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: startPoint.x - app.frame.minX,
                dy: startPoint.y - app.frame.minY))
            let end = origin.withOffset(CGVector(dx: startPoint.x - app.frame.minX,
                dy: endY - app.frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
            recordScroll("after-delete-\(index)-one-native-cell-drag")
            let afterFrame = form.frame
            guard abs(afterFrame.minY - beforeFrame.minY) < 2,
                  abs(afterFrame.height - beforeFrame.height) < 2 else {
                XCTFail("Return gesture moved the Form presentation instead of revealing its content.")
                return
            }
            guard row.exists && row.isHittable && usableBounds(of: form, in: app).contains(row.frame) else {
                XCTFail("One controlled native cell drag did not reveal the target; retained geometry requires diagnosis.")
                return
            }
        }
        XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription)
        row.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
    }
}
