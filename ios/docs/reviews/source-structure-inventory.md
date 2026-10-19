# Swift source organization inventory — 2026-10-10

This is a declaration/function-section inventory, not a full behavior audit. Production dependency/body review and completed extractions are documented in source-structure.md and source-structure-railkit-review.md. Native regression files are included for filename/type/helper organization; their cases were not run.

| File | Lines | Top-level owners | Function declarations |
|---|---:|---|---:|
| `RailKit/Sources/RailApplication/Editor/RideDraftValidation.swift` | 273 | RideDraftValidation | 12 |
| `RailKit/Sources/RailApplication/Import/ImportPreflight.swift` | 283 | ImportPreflight | 7 |
| `RailKit/Sources/RailApplication/Import/ImportStaging.swift` | 72 | ImportStaging | 1 |
| `RailKit/Sources/RailApplication/Routing/TripRouteValidation.swift` | 77 | TripRouteValidation | 1 |
| `RailKit/Sources/RailApplication/Statistics/MileageMatching.swift` | 107 | MileageMatching | 1 |
| `RailKit/Sources/RailCore/Data/CompactPackage.swift` | 513 | CompactPackage, CompactPackage, CompactPackage.Line, CompactPackage.Station, CompactPackage.Segment, CompactPackage, CompactPackage, CompactPackage.Line, CompactPackage.Headers, CompactPackage.Headers.Line, CompactPackage | 8 |
| `RailKit/Sources/RailCore/Data/DatasetManifestIndex.swift` | 46 | DatasetManifestIndex | 0 |
| `RailKit/Sources/RailCore/Data/DisplayChunkReader.swift` | 35 | DisplayChunkError, DisplayChunkReader | 1 |
| `RailKit/Sources/RailCore/Data/RailResourceRevisions.swift` | 54 | RailResourceRevisions | 3 |
| `RailKit/Sources/RailCore/Editor/EditorAIEligibility.swift` | 73 | EditorAIDenial, EditorAIStop, EditorAIEligibility | 2 |
| `RailKit/Sources/RailCore/Editor/EditorCatalog.swift` | 617 | StationKey, OperatorRedirect, CatalogOperator, CatalogLine, CatalogStation, StationLineMembership, EditorCatalogIssue, EditorCatalogLineSource, EditorCatalogStationSource, EditorCatalog, EditorCatalogBuilder, EditorCatalogBuilder, EditorCatalogLineKey, EditorCatalogMatch, EditorCatalogIdentity, EditorCatalogRedirects, EditorCatalogOperatorAcc, EditorCatalogStationAcc | 28 |
| `RailKit/Sources/RailCore/Editor/EditorTime.swift` | 250 | ServiceClockTime, ServiceTimeParse, EditorTimeInput, ServiceDateParse, EditorTime | 16 |
| `RailKit/Sources/RailCore/Editor/LocalJourneyAutofill.swift` | 63 | LocalJourneyAutofill | 1 |
| `RailKit/Sources/RailCore/Editor/RailwayRouteEditing.swift` | 342 | RailwayRouteEditing | 20 |
| `RailKit/Sources/RailCore/Editor/RouteSectionServiceEditing.swift` | 75 | RouteSectionServiceInfo, RouteSectionServiceEditing | 3 |
| `RailKit/Sources/RailCore/History/PhysicalRailJunctionRegistry.swift` | 134 | PhysicalRailJunctionRegistry | 6 |
| `RailKit/Sources/RailCore/History/RailHistory.swift` | 730 | RailHistoryRevisionSet, RailPrecomputedSolverContext, RailPrecomputedRouteGate, RailServiceValidity, RailHistoryOverlay, RailHistory | 24 |
| `RailKit/Sources/RailCore/History/RailHistoryStations.swift` | 124 | RetiredStation, RailHistoryStations | 5 |
| `RailKit/Sources/RailCore/Identity/Localization.swift` | 795 | Localization, JSStringKey | 29 |
| `RailKit/Sources/RailCore/Identity/OperatorBranding.swift` | 921 | OperatorBranding, CodeUnitTable, CodeUnitSet, JSText | 21 |
| `RailKit/Sources/RailCore/Identity/OperatorIdentity.swift` | 146 | OperatorIdentity | 10 |
| `RailKit/Sources/RailCore/Identity/TrainServiceBranding.swift` | 409 | TrainServiceBranding, Character | 19 |
| `RailKit/Sources/RailCore/Import/ChatGPTSubscriptionProtocol.swift` | 502 | ChatGPTSubscriptionProtocol, ChatGPTSubscriptionProtocol | 19 |
| `RailKit/Sources/RailCore/Import/ImportEngine.swift` | 970 | ImportEngine | 22 |
| `RailKit/Sources/RailCore/Import/JREastGuide.swift` | 487 | TransferGuide | 20 |
| `RailKit/Sources/RailCore/Import/JourneyCompletion.swift` | 1275 | JourneyCompletion, JourneyCompletion, JourneyCompletion, JourneyCompletion | 43 |
| `RailKit/Sources/RailCore/Import/JourneyTextImport.swift` | 339 | JourneyCompletion, JourneyCompletion | 14 |
| `RailKit/Sources/RailCore/Import/TransferGuide.swift` | 1272 | TransferGuide | 36 |
| `RailKit/Sources/RailCore/Import/TransferGuideText.swift` | 910 | TransferGuide | 34 |
| `RailKit/Sources/RailCore/Import/TransferGuideTrains.swift` | 410 | TransferGuide, Dates | 14 |
| `RailKit/Sources/RailCore/Journeys/CanonicalTrainStoreJSON.swift` | 127 | CanonicalTrainStoreJSON | 6 |
| `RailKit/Sources/RailCore/Journeys/JourneyEnglishName.swift` | 66 | JourneyEnglishName | 3 |
| `RailKit/Sources/RailCore/Journeys/JourneyGroup.swift` | 34 | JourneyGroup | 1 |
| `RailKit/Sources/RailCore/Journeys/ServiceCaption.swift` | 115 | ServiceCaption | 4 |
| `RailKit/Sources/RailCore/Journeys/StoreOperations.swift` | 782 | StoreOperations, StoreOperations, StoreOperations | 27 |
| `RailKit/Sources/RailCore/Journeys/Train.swift` | 2437 | RouteConfirmation, TrainStore, Train, Stop, RouteSection, RoutePolicy, TrainStyle, TrainValidation, TrainValidation, TrainValidation.JSON | 88 |
| `RailKit/Sources/RailCore/Rendering/ContinuousStroke.swift` | 2817 | ContinuousStroke | 92 |
| `RailKit/Sources/RailCore/Rendering/DisplayParts.swift` | 1463 | DisplayParts | 46 |
| `RailKit/Sources/RailCore/Rendering/Grooming.swift` | 338 | Grooming | 11 |
| `RailKit/Sources/RailCore/Rendering/LaneLOD.swift` | 83 | LaneLOD | 2 |
| `RailKit/Sources/RailCore/Rendering/OverlapLanes.swift` | 3475 | OverlapLanes | 123 |
| `RailKit/Sources/RailCore/Rendering/Playback.swift` | 1142 | Playback | 32 |
| `RailKit/Sources/RailCore/Rendering/RideMarkerVisibility.swift` | 46 | RideMarkerVisibility | 2 |
| `RailKit/Sources/RailCore/Rendering/StationDisplay.swift` | 1083 | StationDisplay, Cell | 31 |
| `RailKit/Sources/RailCore/Rendering/StationJoinSmoothing.swift` | 1219 | StationJoinSmoothing | 31 |
| `RailKit/Sources/RailCore/Rendering/StationVisibility.swift` | 124 | Visibility | 2 |
| `RailKit/Sources/RailCore/Rendering/StrokeRide.swift` | 425 | ChainRef, StrokeRef, StrokeRide | 15 |
| `RailKit/Sources/RailCore/Rendering/Visibility.swift` | 68 | Visibility | 5 |
| `RailKit/Sources/RailCore/Routing/LocalJourneySearch.swift` | 477 | LocalJourneySearch, CompactPackage.Line | 21 |
| `RailKit/Sources/RailCore/Routing/PhysicalRouteMatcher.swift` | 454 | RouteNetwork | 22 |
| `RailKit/Sources/RailCore/Routing/PrecomputedRouteDisplay.swift` | 52 | RouteNetwork | 1 |
| `RailKit/Sources/RailCore/Routing/RailwayDirection.swift` | 30 | RailwayDirection | 1 |
| `RailKit/Sources/RailCore/Routing/RailwayRouteChoices.swift` | 107 | RailwayRouteChoices | 4 |
| `RailKit/Sources/RailCore/Routing/RailwayRouteInference.swift` | 104 | RailwayRouteInference | 6 |
| `RailKit/Sources/RailCore/Routing/ResolvedRailRoute.swift` | 66 | ResolvedRailLine, RouteNetwork | 2 |
| `RailKit/Sources/RailCore/Routing/ResolvedRouteExport.swift` | 59 | ResolvedRouteExport | 1 |
| `RailKit/Sources/RailCore/Routing/RouteBatchInspection.swift` | 326 | RouteBatchInspection | 5 |
| `RailKit/Sources/RailCore/Routing/RouteConfirmationRepair.swift` | 13 | RouteConfirmationRepair | 1 |
| `RailKit/Sources/RailCore/Routing/RouteGraph.swift` | 3206 | RouteGraph, RouteGraph, RouteGraph, Coordinate, RouteGraph, RouteGraph.SectionFeature | 114 |
| `RailKit/Sources/RailCore/Routing/RouteNetwork.swift` | 974 | RouteGeometry, RouteHints, RouteFeature, CanonicalRoute, RouteProjectionCache, RouteNetwork | 23 |
| `RailKit/Sources/RailCore/Routing/RouteRepair.swift` | 158 | RouteRepair | 6 |
| `RailKit/Sources/RailCore/Routing/RouteResolutionMemo.swift` | 247 | RouteResolutionMemo | 9 |
| `RailKit/Sources/RailCore/Routing/RouteSolveLimiter.swift` | 74 | entry/support | 4 |
| `RailKit/Sources/RailCore/Routing/RouteSolver.swift` | 4185 | RouteSolver | 160 |
| `RailKit/Sources/RailCore/Routing/SharedRouteWork.swift` | 228 | entry/support | 8 |
| `RailKit/Sources/RailCore/Routing/StationIntervalResolver.swift` | 351 | StationIntervalResolver | 9 |
| `RailKit/Sources/RailCore/Routing/TokyoConventionalRouteInference.swift` | 137 | TokyoConventionalRouteInference | 8 |
| `RailKit/Sources/RailCore/Routing/TravelDirection.swift` | 236 | TravelDirection | 12 |
| `RailKit/Sources/RailCore/Routing/TripConnectivity.swift` | 42 | TripConnectivity | 4 |
| `RailKit/Sources/RailCore/Routing/TripRoutePlanner.swift` | 321 | TripRoutePlanner | 10 |
| `RailKit/Sources/RailCore/Stations/RailIntervalCodes.swift` | 39 | RailIntervalCodes | 1 |
| `RailKit/Sources/RailCore/Stations/StationCodeAliases.swift` | 42 | StationCodeAliases | 1 |
| `RailKit/Sources/RailCore/Stations/StationIndex.swift` | 359 | StationIndex | 11 |
| `RailKit/Sources/RailCore/Stations/StationRouteEligibility.swift` | 79 | StationRouteEligibility | 3 |
| `RailKit/Sources/RailCore/Stations/Stations.swift` | 1252 | StationRouteResolver, Stations, Stations.Value, Stations.Value | 54 |
| `RailKit/Sources/RailCore/Statistics/Statistics.swift` | 2324 | Statistics | 71 |
| `RailKit/Sources/RailCore/Timetable/JapanThroughServices.swift` | 583 | JapanThroughServices | 24 |
| `RailKit/Sources/RailCore/Timetable/LineServiceCatalog.swift` | 156 | LineServiceCatalog | 6 |
| `RailKit/Sources/RailCore/Timetable/TimetablePhysicalRouteMatch.swift` | 360 | TimetablePhysicalRouteMatch | 16 |
| `RailKit/Sources/RailCore/Timetable/TimetableSearch.swift` | 73 | TimetableSearch | 3 |
| `RailKit/Sources/RailCore/Timetable/TimetableServiceDayContext.swift` | 27 | TimetableServiceDayContext | 2 |
| `RailKit/Sources/RailCore/Timetable/TimetableTripMatch.swift` | 44 | TimetableTripMatch | 2 |
| `RailKit/Sources/RailCore/Timetable/TrainServicePatterns.swift` | 645 | TrainServicePatterns | 23 |
| `RailKit/Sources/RailCore/Timetable/TrainTimetableDatabase.swift` | 1468 | TrainTimetableDatabase, Array, Array | 57 |
| `RailKit/Sources/RailCore/Utilities/Coordinates.swift` | 68 | Coordinate, Grid | 4 |
| `RailKit/Sources/RailCore/Utilities/Dates.swift` | 810 | Dates | 37 |
| `RailKit/Sources/RailCore/Utilities/Geometry.swift` | 105 | Geometry | 3 |
| `RailKit/Sources/RailCore/Utilities/JSMath.swift` | 174 | JSMath | 7 |
| `RailKit/Sources/RailCore/Utilities/JSNumber.swift` | 144 | JSNumber | 4 |
| `RailKit/Sources/RailCore/Utilities/JSString.swift` | 153 | CodeUnits, JSString | 4 |
| `RailKit/Sources/RailCore/Utilities/SearchFold.swift` | 139 | SearchFold | 7 |
| `RailKit/Sources/RailPresentation/Editing/CatalogLinePreferenceMapping.swift` | 89 | CatalogLinePreference, CatalogLinePreferenceMapping | 2 |
| `RailKit/Sources/RailPresentation/Editing/DraftMapSnapshot.swift` | 97 | DraftStopPin, DraftMapSnapshot, DraftMapPins | 3 |
| `RailKit/Sources/RailPresentation/Editing/JourneyDraftEdits.swift` | 60 | JourneyDraftDeletion, JourneyDraftEdits | 4 |
| `RailKit/Sources/RailPresentation/Editing/JourneyDraftSelection.swift` | 357 | JourneyDraftStop, JourneyDraftConflict, LineChoice, JourneySelectionPrompt, JourneySelectionEvent, JourneySelectionResult, JourneyDraftSelection | 11 |
| `RailKit/Sources/RailPresentation/Journeys/JourneyDetailSnapshot.swift` | 25 | JourneyDetailSnapshot | 1 |
| `RailKit/Sources/RailPresentation/Journeys/JourneyHeroIdentity.swift` | 32 | JourneyHeroIdentity | 1 |
| `RailKit/Sources/RailPresentation/Journeys/JourneyPresentation.swift` | 336 | PresentationText, JourneyWorkspacePhase, JourneyRouteState, RouteLoadPhase, JourneyFailure, JourneyPresentation, StatusPresentation, SecondaryAction, JourneyPresentation, JourneyRouteState | 4 |
| `RailKit/Sources/RailPresentation/Journeys/JourneyPresentationResolver.swift` | 599 | JourneyPresentationResolver, JourneyPresentation.PrimaryAction, SecondaryAction | 20 |
| `RailKit/Sources/RailPresentation/Journeys/JourneyRouteIdentity.swift` | 71 | JourneyRouteIdentity | 6 |
| `RailKit/Sources/RailPresentation/Journeys/JourneySearchMatcher.swift` | 138 | JourneySearchMatcher | 5 |
| `RailKit/Sources/RailPresentation/Journeys/JourneyServiceSections.swift` | 28 | JourneyServiceSections | 1 |
| `RailKit/Sources/RailPresentation/Journeys/JourneyTitle.swift` | 174 | JourneyTitle | 5 |
| `RailKit/Sources/RailPresentation/Journeys/LaunchJourneySelector.swift` | 74 | LaunchJourneySelector | 3 |
| `RailKit/Sources/RailPresentation/Journeys/RideLedger.swift` | 122 | RideLedger | 6 |
| `RailKit/Sources/RailPresentation/Journeys/RouteStatusResolver.swift` | 219 | SectionGap, RouteOutcome, RouteStatusEntry, RideRouteStatus, RouteStatusResolver | 2 |
| `RailKit/Sources/RailPresentation/Map/DisplayNetworkEra.swift` | 129 | DisplayNetworkEra, DisplayTemporalDecoration, DisplayNetworkDash, DisplayNetworkStrokeStyle | 3 |
| `RailKit/Sources/RailPresentation/Map/LongitudeArc.swift` | 84 | LongitudeArc | 2 |
| `RailKit/Sources/RailPresentation/Map/MapCameraPolicy.swift` | 69 | MapCameraPolicy | 6 |
| `RailKit/Sources/RailPresentation/Map/MapRebuildPolicy.swift` | 80 | MapRebuildPolicy | 2 |
| `RailKit/Sources/RailPresentation/Map/MapUpdatePlan.swift` | 88 | MapUpdatePlan, MapDrawChanges | 0 |
| `RailKit/Sources/RailPresentation/Map/NetworkVisibilityPolicy.swift` | 97 | NetworkVisibilityPolicy | 5 |
| `RailKit/Sources/RailPresentation/Map/RideTapResolver.swift` | 211 | RideTapResolver, RideTapResolver | 5 |
| `RailKit/Sources/RailPresentation/Regions/JourneyClock.swift` | 179 | JourneyClock | 8 |
| `RailKit/Sources/RailPresentation/Regions/RegionClock.swift` | 281 | RegionClock | 10 |
| `RailKit/Sources/RailPresentation/Regions/RegionScopeRule.swift` | 195 | RegionScopeRule | 6 |
| `RailKit/Sources/RailPresentation/Stations/StationLabelVisibility.swift` | 47 | StationLabelVisibility | 4 |
| `RailKit/Sources/RailPresentation/Stations/StationPlaceLink.swift` | 634 | StationPlaceLink | 19 |
| `RailKit/Sources/RailPresentation/Statistics/StatisticsDateSelection.swift` | 77 | StatisticsDateSelection | 6 |
| `RailKit/Sources/RailPresentation/Statistics/StatisticsLineCoverage.swift` | 51 | StatisticsLineCoverage | 1 |
| `RailKit/Sources/RailPresentation/Workspace/PanelDetentResolver.swift` | 192 | PanelDetent, PanelDetentResolver | 4 |
| `RailKit/Sources/RailPresentation/Workspace/PickDuringRunRule.swift` | 37 | PickDuringRunRule | 1 |
| `RailKit/Sources/RailPresentation/Workspace/WorkspaceJourneyRules.swift` | 176 | JourneyDay, WorkspaceJourneyRules | 7 |
| `RailKit/Sources/RailPresentation/Workspace/WorkspaceLayoutPolicy.swift` | 94 | WorkspaceLayoutMode, WorkspaceLayoutPolicy | 0 |
| `RailKit/Tests/RailApplicationTests/ImportPreflightTests.swift` | 250 | ImportPreflightTests, ProgressRecorder | 17 |
| `RailKit/Tests/RailApplicationTests/ImportStagingTests.swift` | 136 | ImportStagingTests, StagingProgressRecorder | 10 |
| `RailKit/Tests/RailApplicationTests/MileageMatchingTests.swift` | 172 | MileageMatchingTests, MileageProgressRecorder | 11 |
| `RailKit/Tests/RailApplicationTests/RideDraftValidationTests.swift` | 141 | RideDraftValidationTests, Array | 7 |
| `RailKit/Tests/RailApplicationTests/TripRouteValidationTests.swift` | 171 | TripRouteValidationTests | 14 |
| `RailKit/Tests/RailCoreTests/ChatGPTSubscriptionProtocolTests.swift` | 238 | ChatGPTSubscriptionProtocolTests | 18 |
| `RailKit/Tests/RailCoreTests/CompactPackageHeadersTests.swift` | 130 | CompactPackageHeadersTests | 4 |
| `RailKit/Tests/RailCoreTests/CompactPackageLoopTests.swift` | 239 | CompactPackageLoopTests | 9 |
| `RailKit/Tests/RailCoreTests/CompiledRouteGraphEquivalenceTests.swift` | 228 | CompiledRouteGraphEquivalenceTests | 9 |
| `RailKit/Tests/RailCoreTests/ContinuousStrokeBendPreservationTests.swift` | 319 | ContinuousStrokeBendPreservationTests | 9 |
| `RailKit/Tests/RailCoreTests/ContinuousStrokeCurveTests.swift` | 312 | ContinuousStrokeCurveTests | 18 |
| `RailKit/Tests/RailCoreTests/ContinuousStrokeMinimumRadiusTests.swift` | 203 | ContinuousStrokeMinimumRadiusTests | 10 |
| `RailKit/Tests/RailCoreTests/ContinuousStrokeParityTests.swift` | 847 | ContinuousStrokeParityTests | 30 |
| `RailKit/Tests/RailCoreTests/ContinuousStrokePointAlongTests.swift` | 95 | ContinuousStrokePointAlongTests | 3 |
| `RailKit/Tests/RailCoreTests/DatasetManifestIndexTests.swift` | 40 | DatasetManifestIndexTests | 4 |
| `RailKit/Tests/RailCoreTests/DatedEndpointNameShadowTests.swift` | 223 | DatedEndpointNameShadowTests | 8 |
| `RailKit/Tests/RailCoreTests/DatesParityTests.swift` | 529 | DatesParityTests | 19 |
| `RailKit/Tests/RailCoreTests/DefensiveHardeningTests.swift` | 138 | DefensiveHardeningTests | 10 |
| `RailKit/Tests/RailCoreTests/DirectionalAlignmentSelectionTests.swift` | 194 | DirectionalAlignmentSelectionTests | 8 |
| `RailKit/Tests/RailCoreTests/DisplayChunkReaderTests.swift` | 103 | DisplayChunkReaderTests | 7 |
| `RailKit/Tests/RailCoreTests/DisplayPartsParityTests.swift` | 714 | DisplayPartsParityTests | 17 |
| `RailKit/Tests/RailCoreTests/EdgeJunctionValueSemanticsTests.swift` | 101 | EdgeJunctionValueSemanticsTests | 5 |
| `RailKit/Tests/RailCoreTests/EditorCatalogTests.swift` | 312 | EditorCatalogTests | 18 |
| `RailKit/Tests/RailCoreTests/EditorTimeTests.swift` | 200 | EditorTimeTests | 13 |
| `RailKit/Tests/RailCoreTests/ExpressDatabaseDisplayCensusTests.swift` | 633 | ExpressDatabaseDisplayCensusTests | 18 |
| `RailKit/Tests/RailCoreTests/FamilyWindowParityTests.swift` | 187 | FamilyWindowParityTests | 4 |
| `RailKit/Tests/RailCoreTests/FixtureParityTests.swift` | 324 | FixtureParityTests | 12 |
| `RailKit/Tests/RailCoreTests/GraphCachePolicyTests.swift` | 128 | GraphCachePolicyTests | 6 |
| `RailKit/Tests/RailCoreTests/GroomingParityTests.swift` | 346 | GroomingParityTests | 8 |
| `RailKit/Tests/RailCoreTests/HakodateRouteConnectionTests.swift` | 97 | HakodateRouteConnectionTests | 3 |
| `RailKit/Tests/RailCoreTests/ImportParityTests.swift` | 711 | ImportParityTests, ImportEngine.Part | 20 |
| `RailKit/Tests/RailCoreTests/JSONParserTests.swift` | 78 | JSONParserTests | 6 |
| `RailKit/Tests/RailCoreTests/JapanThroughHistoricalRepairsTests.swift` | 112 | JapanThroughHistoricalRepairsTests | 10 |
| `RailKit/Tests/RailCoreTests/JapanThroughServicesTests.swift` | 767 | JapanThroughServicesTests | 40 |
| `RailKit/Tests/RailCoreTests/JourneyCompletionTests.swift` | 754 | JourneyCompletionTests | 34 |
| `RailKit/Tests/RailCoreTests/JourneyEnglishNameTests.swift` | 72 | JourneyEnglishNameTests | 5 |
| `RailKit/Tests/RailCoreTests/JourneyGroupTests.swift` | 106 | JourneyGroupTests | 7 |
| `RailKit/Tests/RailCoreTests/JourneyLifecycleTests.swift` | 226 | JourneyLifecycleTests | 8 |
| `RailKit/Tests/RailCoreTests/JourneyThroughCompletionTests.swift` | 182 | JourneyThroughCompletionTests | 13 |
| `RailKit/Tests/RailCoreTests/JunctionApproachTests.swift` | 659 | JunctionApproachTests | 21 |
| `RailKit/Tests/RailCoreTests/KoreanServiceGroupTests.swift` | 73 | KoreanServiceGroupTests | 7 |
| `RailKit/Tests/RailCoreTests/LaneLODTests.swift` | 106 | LaneLODTests | 2 |
| `RailKit/Tests/RailCoreTests/LineServiceCatalogTests.swift` | 102 | LineServiceCatalogTests | 7 |
| `RailKit/Tests/RailCoreTests/LocalJourneyAutofillTests.swift` | 100 | LocalJourneyAutofillTests | 7 |
| `RailKit/Tests/RailCoreTests/LocalJourneySearchTests.swift` | 252 | LocalJourneySearchTests, LocalJourneySearchTests | 19 |
| `RailKit/Tests/RailCoreTests/LocalizationParityTests.swift` | 838 | LocalizationParityTests | 26 |
| `RailKit/Tests/RailCoreTests/OSMTrackConnectorTests.swift` | 403 | OSMTrackConnectorTests | 32 |
| `RailKit/Tests/RailCoreTests/OnEdgeCertificationTests.swift` | 545 | OnEdgeCertificationTests | 32 |
| `RailKit/Tests/RailCoreTests/OperatorBrandingParityTests.swift` | 295 | OperatorBrandingParityTests | 12 |
| `RailKit/Tests/RailCoreTests/OperatorIdentityTests.swift` | 139 | OperatorIdentityTests | 8 |
| `RailKit/Tests/RailCoreTests/OperatorLogoSpellingTests.swift` | 43 | OperatorLogoSpellingTests | 4 |
| `RailKit/Tests/RailCoreTests/OverlapLanesParityTests.swift` | 846 | OverlapLanesParityTests | 13 |
| `RailKit/Tests/RailCoreTests/PendingRouteConfirmationTests.swift` | 76 | PendingRouteConfirmationTests | 6 |
| `RailKit/Tests/RailCoreTests/PhysicalEndpointTrimTests.swift` | 524 | PhysicalEndpointTrimPart, PhysicalEndpointTrimTests | 19 |
| `RailKit/Tests/RailCoreTests/PhysicalSectionContinuityTests.swift` | 221 | PhysicalSectionContinuityTests | 13 |
| `RailKit/Tests/RailCoreTests/PhysicalTopologyRoutingTests.swift` | 390 | PhysicalTopologyRoutingTests | 27 |
| `RailKit/Tests/RailCoreTests/PlaybackParityTests.swift` | 1200 | PlaybackParityTests | 25 |
| `RailKit/Tests/RailCoreTests/PlaybackTrailTests.swift` | 78 | PlaybackTrailTests | 4 |
| `RailKit/Tests/RailCoreTests/PortFixtures.swift` | 96 | PortFixtures, Double | 5 |
| `RailKit/Tests/RailCoreTests/PrecomputedRouteDisplayTests.swift` | 116 | PrecomputedRouteDisplayTests | 4 |
| `RailKit/Tests/RailCoreTests/RailHistoryIdentityTests.swift` | 96 | RailHistoryIdentityTests | 6 |
| `RailKit/Tests/RailCoreTests/RailHistoryPackageTests.swift` | 658 | RailHistoryPackageTests | 38 |
| `RailKit/Tests/RailCoreTests/RailHistoryStationsTests.swift` | 109 | RailHistoryStationsTests | 8 |
| `RailKit/Tests/RailCoreTests/RailHistoryTests.swift` | 752 | RailHistoryTests | 33 |
| `RailKit/Tests/RailCoreTests/RailIntervalCodeTests.swift` | 95 | RailIntervalCodeTests | 4 |
| `RailKit/Tests/RailCoreTests/RailResourceRevisionsTests.swift` | 65 | RailResourceRevisionsTests | 3 |
| `RailKit/Tests/RailCoreTests/RailValidityTests.swift` | 365 | RailValidityTests | 27 |
| `RailKit/Tests/RailCoreTests/RailwayRouteChoicesTests.swift` | 267 | RailwayRouteChoicesTests | 19 |
| `RailKit/Tests/RailCoreTests/RailwayRouteEditingTests.swift` | 288 | RailwayRouteEditingTests | 16 |
| `RailKit/Tests/RailCoreTests/RailwayRouteInferenceTests.swift` | 392 | RailwayRouteInferenceTests, SamplePart | 23 |
| `RailKit/Tests/RailCoreTests/RejoiningRailwayFamiliesTests.swift` | 137 | RejoiningRailwayFamiliesTests | 4 |
| `RailKit/Tests/RailCoreTests/ResolvedRailRouteTests.swift` | 106 | ResolvedRailRouteTests | 8 |
| `RailKit/Tests/RailCoreTests/ResolvedRouteExportTests.swift` | 64 | ResolvedRouteExportTests | 8 |
| `RailKit/Tests/RailCoreTests/ReviewedChayamachiRoutingTests.swift` | 116 | ReviewedChayamachiRoutingTests | 4 |
| `RailKit/Tests/RailCoreTests/ReviewedHimejiRoutingTests.swift` | 77 | ReviewedHimejiRoutingTests | 2 |
| `RailKit/Tests/RailCoreTests/ReviewedIwanumaRoutingTests.swift` | 92 | ReviewedIwanumaRoutingTests | 2 |
| `RailKit/Tests/RailCoreTests/ReviewedKobeRoutingTests.swift` | 79 | ReviewedKobeRoutingTests | 2 |
| `RailKit/Tests/RailCoreTests/ReviewedShiojiriRoutingTests.swift` | 57 | ReviewedShiojiriRoutingTests | 2 |
| `RailKit/Tests/RailCoreTests/ReviewedUtazuRoutingTests.swift` | 129 | ReviewedUtazuRoutingTests | 2 |
| `RailKit/Tests/RailCoreTests/RideMarkerVisibilityTests.swift` | 68 | RideMarkerVisibilityTests | 5 |
| `RailKit/Tests/RailCoreTests/RouteBatchInspectionTests.swift` | 236 | RouteBatchInspectionTests | 20 |
| `RailKit/Tests/RailCoreTests/RouteConfirmationRepairTests.swift` | 69 | RouteConfirmationRepairTests | 6 |
| `RailKit/Tests/RailCoreTests/RouteDirectionAndBranchTests.swift` | 257 | RouteDirectionAndBranchTests | 11 |
| `RailKit/Tests/RailCoreTests/RouteFeatureParityTests.swift` | 356 | RouteFeatureParityTests | 8 |
| `RailKit/Tests/RailCoreTests/RouteGraphParityTests.swift` | 606 | RouteGraphParityTests | 14 |
| `RailKit/Tests/RailCoreTests/RouteHintsParityTests.swift` | 128 | RouteHintsParityTests | 6 |
| `RailKit/Tests/RailCoreTests/RouteRepairTests.swift` | 123 | RouteRepairTests | 8 |
| `RailKit/Tests/RailCoreTests/RouteResolutionMemoTests.swift` | 341 | RouteResolutionMemoTests | 15 |
| `RailKit/Tests/RailCoreTests/RouteSectionExportTests.swift` | 92 | RouteSectionExportTests | 8 |
| `RailKit/Tests/RailCoreTests/RouteSectionPairIndexTests.swift` | 89 | RouteSectionPairIndexTests | 7 |
| `RailKit/Tests/RailCoreTests/RouteSectionServiceEditingTests.swift` | 92 | RouteSectionServiceEditingTests | 5 |
| `RailKit/Tests/RailCoreTests/RouteSectionSolveParityTests.swift` | 336 | RouteSectionSolveParityTests | 12 |
| `RailKit/Tests/RailCoreTests/RouteSolveLimiterTests.swift` | 186 | RouteSolveLimiterTests | 10 |
| `RailKit/Tests/RailCoreTests/RouteSolverEndpointPreflightTests.swift` | 108 | RouteSolverEndpointPreflightTests | 5 |
| `RailKit/Tests/RailCoreTests/RouteSolverParityTests.swift` | 297 | RouteSolverParityTests | 9 |
| `RailKit/Tests/RailCoreTests/RouteStationCandidatesParityTests.swift` | 120 | RouteStationCandidatesParityTests | 5 |
| `RailKit/Tests/RailCoreTests/RouteStoreStressTests.swift` | 331 | RouteStoreStressTests | 12 |
| `RailKit/Tests/RailCoreTests/SamplePrecomputeProvenanceTests.swift` | 184 | SamplePrecomputeProvenanceTests | 5 |
| `RailKit/Tests/RailCoreTests/SampleServiceConformanceTests.swift` | 122 | SampleServiceConformanceTests | 4 |
| `RailKit/Tests/RailCoreTests/SampleStoreUpgradeTests.swift` | 57 | SampleStoreUpgradeTests | 1 |
| `RailKit/Tests/RailCoreTests/SearchFoldTests.swift` | 46 | SearchFoldTests | 4 |
| `RailKit/Tests/RailCoreTests/ServiceCaptionTests.swift` | 89 | ServiceCaptionTests | 6 |
| `RailKit/Tests/RailCoreTests/SharedRouteWorkTests.swift` | 301 | SharedRouteWorkTests | 17 |
| `RailKit/Tests/RailCoreTests/ShortLinkJunctionTests.swift` | 110 | ShortLinkJunctionTests | 14 |
| `RailKit/Tests/RailCoreTests/SonicRouteConstraintTests.swift` | 67 | SonicRouteConstraintTests | 6 |
| `RailKit/Tests/RailCoreTests/StationCodeAliasesTests.swift` | 66 | StationCodeAliasesTests | 7 |
| `RailKit/Tests/RailCoreTests/StationDisplayParityTests.swift` | 1108 | StationDisplayParityTests | 32 |
| `RailKit/Tests/RailCoreTests/StationIntervalResolverTests.swift` | 240 | StationIntervalResolverTests | 21 |
| `RailKit/Tests/RailCoreTests/StationJoinSmoothingParityTests.swift` | 675 | StationJoinSmoothingParityTests | 12 |
| `RailKit/Tests/RailCoreTests/StationNameFieldsTests.swift` | 101 | StationNameFieldsTests | 6 |
| `RailKit/Tests/RailCoreTests/StationReversalTests.swift` | 52 | StationReversalTests | 4 |
| `RailKit/Tests/RailCoreTests/StationRouteEligibilityTests.swift` | 135 | StationRouteEligibilityTests | 12 |
| `RailKit/Tests/RailCoreTests/StationVisibilityParityTests.swift` | 142 | StationVisibilityParityTests | 4 |
| `RailKit/Tests/RailCoreTests/StationsParityTests.swift` | 969 | StationsParityTests | 34 |
| `RailKit/Tests/RailCoreTests/StatisticsParityTests.swift` | 1139 | StatisticsParityTests | 30 |
| `RailKit/Tests/RailCoreTests/StoreOperationsParityTests.swift` | 688 | StoreOperationsParityTests | 18 |
| `RailKit/Tests/RailCoreTests/StoreRoundTripTests.swift` | 195 | StoreRoundTripTests | 11 |
| `RailKit/Tests/RailCoreTests/StrokeRideTests.swift` | 214 | StrokeRideTests | 12 |
| `RailKit/Tests/RailCoreTests/SupportedRegionTests.swift` | 46 | SupportedRegionTests | 5 |
| `RailKit/Tests/RailCoreTests/TemporalEdgeStatisticsTests.swift` | 200 | TemporalEdgeStatisticsTests | 7 |
| `RailKit/Tests/RailCoreTests/TemporalRouteFastPathTests.swift` | 106 | TemporalRouteFastPathTests | 9 |
| `RailKit/Tests/RailCoreTests/TimetableAppFlowTests.swift` | 185 | TimetableAppFlowTests | 7 |
| `RailKit/Tests/RailCoreTests/TimetableCountryScopeTests.swift` | 45 | TimetableCountryScopeTests | 2 |
| `RailKit/Tests/RailCoreTests/TimetablePhysicalRouteMatchTests.swift` | 246 | TimetablePhysicalRouteMatchTests | 17 |
| `RailKit/Tests/RailCoreTests/TimetableQuickMatchReportTests.swift` | 53 | TimetableQuickMatchReportTests | 2 |
| `RailKit/Tests/RailCoreTests/TimetableSearchTests.swift` | 69 | TimetableSearchTests | 7 |
| `RailKit/Tests/RailCoreTests/TimetableServiceDayContextTests.swift` | 19 | TimetableServiceDayContextTests | 2 |
| `RailKit/Tests/RailCoreTests/TokyoConventionalRouteInferenceTests.swift` | 95 | TokyoConventionalRouteInferenceTests | 7 |
| `RailKit/Tests/RailCoreTests/TrainServiceBrandingTests.swift` | 330 | TrainServiceBrandingTests | 27 |
| `RailKit/Tests/RailCoreTests/TrainServiceCatalogChecklistTests.swift` | 188 | TrainServiceCatalogChecklistTests | 6 |
| `RailKit/Tests/RailCoreTests/TrainServicePatternAcceptance.swift` | 190 | TrainServicePatternAcceptance | 19 |
| `RailKit/Tests/RailCoreTests/TrainServicePatternPersistenceTests.swift` | 218 | TrainServicePatternPersistenceTests | 7 |
| `RailKit/Tests/RailCoreTests/TrainServicePatternReportContractTests.swift` | 126 | entry/support | 8 |
| `RailKit/Tests/RailCoreTests/TrainServicePatternRouteTests.swift` | 556 | TrainServicePatternRouteTests | 17 |
| `RailKit/Tests/RailCoreTests/TrainServicePatternsTests.swift` | 689 | TrainServicePatternsTests | 32 |
| `RailKit/Tests/RailCoreTests/TrainTimetableDatabaseTests.swift` | 817 | TrainTimetableDatabaseTests, FixtureDatabase | 29 |
| `RailKit/Tests/RailCoreTests/TrainValidationParityTests.swift` | 663 | TrainValidationParityTests | 23 |
| `RailKit/Tests/RailCoreTests/TransferGuideRetiredStationTests.swift` | 61 | TransferGuideRetiredStationTests | 3 |
| `RailKit/Tests/RailCoreTests/TransferGuideStationNameTests.swift` | 88 | TransferGuideStationNameTests | 5 |
| `RailKit/Tests/RailCoreTests/TransferGuideTests.swift` | 916 | Screenshot, TransferGuideParseTests, TransferGuideTextTests, TransferGuideTrainTests, JREastGuideTests | 55 |
| `RailKit/Tests/RailCoreTests/TravelDirectionTests.swift` | 270 | TravelDirectionTests | 18 |
| `RailKit/Tests/RailCoreTests/TraversedLinesTests.swift` | 142 | TraversedLinesTests | 12 |
| `RailKit/Tests/RailCoreTests/TripRoutePlannerTests.swift` | 349 | TripRoutePlannerTests, TripRoutePlannerTests | 23 |
| `RailKit/Tests/RailPresentationTests/DisplayNetworkEraTests.swift` | 107 | DisplayNetworkEraTests | 11 |
| `RailKit/Tests/RailPresentationTests/DraftMapDateTests.swift` | 39 | DraftMapDateTests | 3 |
| `RailKit/Tests/RailPresentationTests/DraftMapSnapshotTests.swift` | 108 | DraftMapSnapshotTests | 7 |
| `RailKit/Tests/RailPresentationTests/JourneyDetailSnapshotTests.swift` | 31 | JourneyDetailSnapshotTests | 2 |
| `RailKit/Tests/RailPresentationTests/JourneyHeroIdentityTests.swift` | 39 | JourneyHeroIdentityTests | 4 |
| `RailKit/Tests/RailPresentationTests/JourneyPresentationResolverTests.swift` | 522 | JourneyPresentationResolverTests | 30 |
| `RailKit/Tests/RailPresentationTests/JourneyRouteIdentityTests.swift` | 195 | JourneyRouteIdentityTests | 24 |
| `RailKit/Tests/RailPresentationTests/JourneySearchMatcherTests.swift` | 532 | JourneySearchMatcherTests, JourneySearchMatcherLocalizedNameTests, JourneySearchMatcherFastPathTests | 38 |
| `RailKit/Tests/RailPresentationTests/JourneyServiceSectionsTests.swift` | 45 | JourneyServiceSectionsTests | 4 |
| `RailKit/Tests/RailPresentationTests/JourneyTitleTests.swift` | 137 | JourneyTitleTests | 15 |
| `RailKit/Tests/RailPresentationTests/LaunchJourneySelectorTests.swift` | 101 | LaunchJourneySelectorTests | 8 |
| `RailKit/Tests/RailPresentationTests/LongitudeArcTests.swift` | 95 | LongitudeArcTests | 6 |
| `RailKit/Tests/RailPresentationTests/MapCameraPolicyTests.swift` | 126 | MapCameraPolicyTests | 10 |
| `RailKit/Tests/RailPresentationTests/MapRebuildPolicyTests.swift` | 97 | MapRebuildPolicyTests | 6 |
| `RailKit/Tests/RailPresentationTests/MapUpdatePlanTests.swift` | 139 | MapUpdatePlanTests | 18 |
| `RailKit/Tests/RailPresentationTests/NetworkVisibilityPolicyTests.swift` | 151 | NetworkVisibilityPolicyTests | 13 |
| `RailKit/Tests/RailPresentationTests/PanelDetentResolverTests.swift` | 219 | PanelDetentResolverTests | 18 |
| `RailKit/Tests/RailPresentationTests/PickDuringRunRuleTests.swift` | 30 | PickDuringRunRuleTests | 4 |
| `RailKit/Tests/RailPresentationTests/RegionClockTests.swift` | 279 | RegionClockTests | 18 |
| `RailKit/Tests/RailPresentationTests/RegionScopeRuleTests.swift` | 143 | RegionScopeRuleTests | 11 |
| `RailKit/Tests/RailPresentationTests/RideLedgerTests.swift` | 166 | RideLedgerTests | 13 |
| `RailKit/Tests/RailPresentationTests/RideTapCullTests.swift` | 180 | RideTapCullTests, Deterministic | 10 |
| `RailKit/Tests/RailPresentationTests/RideTapResolverTests.swift` | 90 | RideTapResolverTests | 10 |
| `RailKit/Tests/RailPresentationTests/RouteStatusResolverTests.swift` | 221 | RouteStatusResolverTests | 20 |
| `RailKit/Tests/RailPresentationTests/StationLabelVisibilityTests.swift` | 82 | StationLabelVisibilityTests | 7 |
| `RailKit/Tests/RailPresentationTests/StationLineSelectionTests.swift` | 351 | StationLineSelectionTests, Fixture | 19 |
| `RailKit/Tests/RailPresentationTests/StationPlaceLinkTests.swift` | 433 | StationPlaceLinkTests | 38 |
| `RailKit/Tests/RailPresentationTests/StatisticsDateSelectionTests.swift` | 142 | StatisticsDateSelectionTests | 8 |
| `RailKit/Tests/RailPresentationTests/StatisticsLineCoverageTests.swift` | 120 | StatisticsLineCoverageTests | 6 |
| `RailKit/Tests/RailPresentationTests/WorkspaceJourneyRulesTests.swift` | 169 | WorkspaceJourneyRulesTests | 9 |
| `RailKit/Tests/RailPresentationTests/WorkspaceLayoutPolicyTests.swift` | 103 | WorkspaceLayoutPolicyTests | 5 |
| `RailMap/App/AppShell.swift` | 367 | AppShell | 0 |
| `RailMap/App/RailMapApp.swift` | 190 | RailMapApp, RailCommandBridge, RailCommandBridgeKey, FocusedValues, RailMapCommands, AppTypographyUITestProbe | 5 |
| `RailMap/Design/AppTypographyPolicy.swift` | 17 | AppTypographyPolicy | 1 |
| `RailMap/Design/ControlSizing.swift` | 49 | RailCapsuleButtonStyle, View | 2 |
| `RailMap/Design/DockedCard.swift` | 33 | DockedCard | 1 |
| `RailMap/Design/GlassStyle.swift` | 217 | View, RailGlassSurface, Color, RailGlassGroup, View, RailOnDockSurfaceKey, EnvironmentValues, ToolbarContent | 10 |
| `RailMap/Design/HexColor.swift` | 66 | HexColor, UIColor, Color | 1 |
| `RailMap/Design/OperatorBadge.swift` | 270 | OperatorBadge | 6 |
| `RailMap/Design/RailMotion.swift` | 358 | RailMotion, RailInterpolatedFont, View, RailPressStyle, RailRowPressStyle | 14 |
| `RailMap/Design/RailStyle.swift` | 392 | RailStyle | 8 |
| `RailMap/Design/RailType.swift` | 133 | RailType, View, RailTypeBounds | 4 |
| `RailMap/Design/RouteLogoSquare.swift` | 256 | RouteLogoSquare, InkFittedArtwork | 3 |
| `RailMap/Design/ScrollableIfNeeded.swift` | 10 | ScrollableIfNeeded | 1 |
| `RailMap/Diagnostics/AppleMapDatumProbe.swift` | 119 | AppleMapDatumProbe | 5 |
| `RailMap/Diagnostics/LongJourneyDetailTestView.swift` | 63 | LongJourneyDetailTestView | 0 |
| `RailMap/Diagnostics/MapIndependentRailPrototype.swift` | 666 | MapIndependentRailPrototype | 20 |
| `RailMap/Diagnostics/MapRenderDiagnostics.swift` | 328 | MapRenderDiagnostics | 19 |
| `RailMap/Diagnostics/ReduceMotionUITestProbe.swift` | 22 | ReduceMotionUITestProbe | 1 |
| `RailMap/Diagnostics/RouteStressHarness.swift` | 390 | RouteStressHarness, RouteStressStatusLabel, RouteStressStatus, RouteStressHarnessPanel | 18 |
| `RailMap/Diagnostics/TabClearanceDiagnostic.swift` | 14 | TabClearanceDiagnostic | 1 |
| `RailMap/Import/DataImportView.swift` | 544 | DataImportView, DataProgressSummaryView, DataIssueRow, DataErrorCard | 5 |
| `RailMap/Import/DataManagerView.swift` | 816 | DataManagerView | 3 |
| `RailMap/Import/ImportFileReader.swift` | 43 | ImportFileReaderError, ImportFileReader | 1 |
| `RailMap/Import/ImportFlow.swift` | 478 | ProgressSummary, ProgressVisibility, ImportFlow | 8 |
| `RailMap/Import/ImportPreflight.swift` | 18 | ImportPreflight.Mode | 0 |
| `RailMap/Import/TrainStoreDocument.swift` | 21 | TrainStoreDocument | 1 |
| `RailMap/Import/TransferGuideImport.swift` | 400 | TransferGuideImport | 14 |
| `RailMap/Import/TransferGuideImportView.swift` | 714 | TransferGuideImportView | 24 |
| `RailMap/Import/TransferGuideOCR.swift` | 499 | TransferGuideOCR | 17 |
| `RailMap/Infrastructure/Duration+Milliseconds.swift` | 8 | Duration | 0 |
| `RailMap/Infrastructure/Network/DisplayNetworkCache.swift` | 140 | entry/support | 6 |
| `RailMap/Infrastructure/Network/EdgeIndexCache.swift` | 378 | entry/support | 16 |
| `RailMap/Infrastructure/Network/EditorCatalogLoading.swift` | 51 | EditorCatalogLoadError, EditorCatalogCache | 3 |
| `RailMap/Infrastructure/Network/JourneyStationAliases.swift` | 31 | JourneyStationIdentity | 2 |
| `RailMap/Infrastructure/Network/RailDisplayNetwork.swift` | 277 | RailDisplayNetwork, SHA256.Digest | 10 |
| `RailMap/Infrastructure/Network/RailDisplayNetworkFormats.swift` | 762 | RailDisplayNetworkManifest, RailDisplayNetworkFile, RailDisplayNetworkError, RailDisplayNetworkIndex, RailDisplayStationTable, RailDisplayHistoryFile | 4 |
| `RailMap/Infrastructure/Network/RailNetworkStore.swift` | 1768 | DisplayDetail, RailNetworkStore | 30 |
| `RailMap/Infrastructure/Network/RailSignpost.swift` | 107 | RailSignpost, OSSignposter | 5 |
| `RailMap/Infrastructure/Network/RegionCatalog.swift` | 572 | Region, RouteScope, Train, LaunchMapScope | 16 |
| `RailMap/Infrastructure/Network/RegionToday.swift` | 50 | RegionToday | 1 |
| `RailMap/Infrastructure/Network/RouteBadgeIndex.swift` | 167 | RouteBadgeIndex | 12 |
| `RailMap/Infrastructure/Network/StationPlaceStore.swift` | 303 | StationPlaceStore | 9 |
| `RailMap/Infrastructure/Network/StationReadingsStore.swift` | 91 | entry/support | 3 |
| `RailMap/Infrastructure/Network/TraversedLineDetector.swift` | 155 | TraversedLineDetector | 5 |
| `RailMap/Infrastructure/Persistence/MergedStore.swift` | 160 | MergedStore | 8 |
| `RailMap/Infrastructure/Persistence/RiddenRouteStore.swift` | 2809 | RiddenRouteStore, PartialRideInbox, PartialRidePublication | 77 |
| `RailMap/Infrastructure/Persistence/RideLibrary.swift` | 443 | RideLibrary | 16 |
| `RailMap/Infrastructure/Persistence/RidePersistenceQueue.swift` | 21 | RidePersistenceQueue | 1 |
| `RailMap/Infrastructure/Persistence/RideStorage.swift` | 273 | entry/support | 19 |
| `RailMap/Infrastructure/Persistence/TimetableRouteEvidence.swift` | 115 | entry/support | 4 |
| `RailMap/Infrastructure/Subscription/ChatGPTSubscriptionAuth.swift` | 806 | ChatGPTSubscriptionAuth, ChatGPTSubscriptionAuth, ChatGPTSubscriptionCredentialStoring, ChatGPTSubscriptionKeychainStorage, ChatGPTSubscriptionNoRedirectDelegate, StoredCredentials, UserCodeRequest, RefreshTokenRequest, DeviceCodeResponse, DeviceTokenRequest, DeviceAuthorizationResponse, TokenResponse | 30 |
| `RailMap/Infrastructure/Subscription/ChatGPTSubscriptionService.swift` | 174 | ChatGPTSubscriptionService, SubscriptionRedirectPolicy | 8 |
| `RailMap/JourneyEditor/AutoFilledStationLabel.swift` | 16 | AutoFilledStationLabel | 0 |
| `RailMap/JourneyEditor/EditorBindings.swift` | 31 | EditorBindings | 2 |
| `RailMap/JourneyEditor/EditorDateTimeFields.swift` | 299 | EditorDateField, EditorTimeField | 0 |
| `RailMap/JourneyEditor/EditorFields.swift` | 133 | EditorField, EditorTextField, EditorSearchField | 1 |
| `RailMap/JourneyEditor/EditorLineSearchView.swift` | 242 | EditorLineSearchView | 3 |
| `RailMap/JourneyEditor/EditorRoutePackageCache.swift` | 27 | EditorRoutePackageCache | 1 |
| `RailMap/JourneyEditor/EditorValidation.swift` | 160 | RideDraftIssue, RideDraftValidation, Array | 4 |
| `RailMap/JourneyEditor/JourneyCompletionRequest.swift` | 33 | JourneyCompletionRequest | 2 |
| `RailMap/JourneyEditor/JourneyCompletionView.swift` | 514 | JourneyCompletionView | 17 |
| `RailMap/JourneyEditor/JourneyEditing.swift` | 154 | JourneyEditing | 11 |
| `RailMap/JourneyEditor/LocalJourneyFillView.swift` | 312 | LocalJourneyFillView | 9 |
| `RailMap/JourneyEditor/LocalLineServicesSection.swift` | 272 | LineServiceCatalogView, LocalJourneyStationPicker, LocalLineServicesSection, LocalLineServiceBrowser | 6 |
| `RailMap/JourneyEditor/NewTripStrings.swift` | 195 | NewTripStrings | 0 |
| `RailMap/JourneyEditor/NewTripView.swift` | 1225 | NewTripView | 35 |
| `RailMap/JourneyEditor/RailwayRouteCorrectionView.swift` | 280 | RailwayRouteCorrectionView | 6 |
| `RailMap/JourneyEditor/RailwayRouteGuideView.swift` | 949 | RailwayRouteGuideView, RailwayGuideGeometry, RailwayGuideMap, RailwayGuideInspectionView | 27 |
| `RailMap/JourneyEditor/RideEditorAI.swift` | 17 | RideEditorAI | 1 |
| `RailMap/JourneyEditor/RideEditorView.swift` | 2449 | RideEditorView | 49 |
| `RailMap/JourneyEditor/RoutePolicyEditorView.swift` | 76 | RoutePolicyEditorView | 3 |
| `RailMap/JourneyEditor/RouteRepairFlow.swift` | 134 | RouteRepairGuide, RouteRepairFlow | 4 |
| `RailMap/JourneyEditor/RouteSectionEditorView.swift` | 139 | RouteSectionLabel, RouteSectionEditorView | 4 |
| `RailMap/JourneyEditor/ServiceRangeEditorView.swift` | 171 | ServiceRangeEditorView | 5 |
| `RailMap/JourneyEditor/StationPickerSearchController.swift` | 122 | CatalogStationRow, StationPickerSearchController | 7 |
| `RailMap/JourneyEditor/StationPickerView.swift` | 353 | StationCatalogText, CatalogStationLineGroup, CatalogStationCompanyGroup, StationPickerView, RetiredStationLabel, CatalogStationLabel, StationLinePickerView | 9 |
| `RailMap/JourneyEditor/StopEditorView.swift` | 453 | StopEditorLabel, StopEditorView | 2 |
| `RailMap/JourneyEditor/TripStationSearchView.swift` | 240 | TripStationSearchView, TripStationSection, TripStationRow, TripStationLine, TripStationIndex | 9 |
| `RailMap/Journeys/ItineraryStore.swift` | 820 | ItineraryStore | 23 |
| `RailMap/Journeys/JourneyBranding.swift` | 254 | JourneyBranding | 13 |
| `RailMap/Journeys/JourneyCardInformation.swift` | 129 | JourneyCardHeading, JourneyStationInformation, JourneyMenuRouteInformation | 1 |
| `RailMap/Journeys/JourneyComponents.swift` | 880 | JourneyStatusBadge, JourneyStateBlock, RouteTimingView, JourneySummaryRow, QuietActionGroup, JourneyPresentation, JourneyRowCardSurface | 23 |
| `RailMap/Journeys/JourneyGroupPicker.swift` | 152 | JourneyGroupCatalog, JourneyGroupChoiceFields, JourneyGroupAssignmentView | 2 |
| `RailMap/Journeys/JourneyListRow.swift` | 198 | JourneyListRow | 0 |
| `RailMap/Journeys/JourneyMenuView.swift` | 169 | WorkspaceJourneyMenu | 2 |
| `RailMap/Journeys/JourneyPresentationBridge.swift` | 257 | JourneyBridge, JourneyActionAppearance, JourneyPresentation.PrimaryAction, SecondaryAction, StatusPresentation.Tone | 5 |
| `RailMap/Journeys/JourneySearch.swift` | 72 | JourneySearch | 1 |
| `RailMap/Journeys/JourneySearchField.swift` | 77 | JourneySearchField | 0 |
| `RailMap/Journeys/RecordDate.swift` | 100 | RecordDate | 5 |
| `RailMap/Journeys/RideCard.swift` | 632 | RideCard, RideIdentityHeaderLayout | 6 |
| `RailMap/Journeys/RideChooserView.swift` | 111 | RideChooserView | 1 |
| `RailMap/Journeys/RideDetailView.swift` | 1330 | DetailActionSizing, WorkspaceRideDetailView, RideDetailView, RideDetailContent, RideRouteStateCard | 20 |
| `RailMap/Journeys/RideRouteStatus.swift` | 146 | RideStatusCenter | 12 |
| `RailMap/Journeys/RideSheet.swift` | 332 | RideRoute, SheetStage, View, ArrivingJourneyCard, SheetIconButton, SheetIconButton, SheetCloseButton, SheetIconLabel, PopupMenuHeader | 1 |
| `RailMap/Journeys/RouteGlyph.swift` | 180 | RouteGlyph, RouteMark | 5 |
| `RailMap/Journeys/StopTimingStatus.swift` | 27 | StopTimingStatus | 3 |
| `RailMap/Journeys/TrainDateBridge.swift` | 26 | Train | 0 |
| `RailMap/Localization/AppLocalization.swift` | 314 | AppLocalization | 15 |
| `RailMap/Localization/AppStrings.swift` | 160 | AppStrings, AppLocalization | 8 |
| `RailMap/Localization/ClockStrings.swift` | 64 | ClockStrings | 0 |
| `RailMap/Localization/DataStrings.swift` | 442 | DataStrings | 0 |
| `RailMap/Localization/EditorStrings.swift` | 1241 | EditorStrings | 0 |
| `RailMap/Localization/JourneyCompletionStrings.swift` | 76 | JourneyCompletionStrings | 0 |
| `RailMap/Localization/JourneyGroupStrings.swift` | 16 | AppLocalization | 1 |
| `RailMap/Localization/JourneyShareStrings.swift` | 25 | AppLocalization | 1 |
| `RailMap/Localization/JourneyStrings.swift` | 562 | JourneyStrings | 0 |
| `RailMap/Localization/LocalJourneyStrings.swift` | 30 | LocalJourneyStrings | 1 |
| `RailMap/Localization/RouteGuideStrings.swift` | 331 | RouteGuideStrings | 0 |
| `RailMap/Localization/ShellStrings.swift` | 450 | ShellStrings | 0 |
| `RailMap/Localization/StationCardStrings.swift` | 72 | StationCardStrings | 0 |
| `RailMap/Localization/StationNaming.swift` | 247 | Train, StationNamingGeneration, AppLocalization | 9 |
| `RailMap/Localization/StatisticsStrings.swift` | 530 | StatisticsStrings | 0 |
| `RailMap/Localization/TransferGuideStrings.swift` | 331 | TransferGuideStrings | 0 |
| `RailMap/Map/AppleMapDatum.swift` | 121 | AppleMapDatum | 8 |
| `RailMap/Map/Coordinate+MapKit.swift` | 9 | Coordinate | 0 |
| `RailMap/Map/JourneyLabelAnnotationViews.swift` | 290 | RideLabelAnnotationView, EndpointLabelView, DraftStopAnnotationView | 8 |
| `RailMap/Map/JourneyLabelAnnotations.swift` | 81 | RideLabelAnnotation, EndpointLabelAnnotation, DraftStopAnnotation | 0 |
| `RailMap/Map/MapAnnotationReconciler.swift` | 351 | MapAnnotationReconciler | 15 |
| `RailMap/Map/MapControlBar.swift` | 375 | MapControlBar, ControlGlyph, ControlButton, MapCompassButton | 3 |
| `RailMap/Map/MapDateScope.swift` | 85 | MapDateScope | 3 |
| `RailMap/Map/MapEndpointLabels.swift` | 348 | MapEndpointLabels | 10 |
| `RailMap/Map/MapInfoView.swift` | 346 | MapInfoView, LegendRow, SourceRow, LegendSymbol, LegendSymbolView | 0 |
| `RailMap/Map/MapInteractionCoordinator.swift` | 232 | MapInteractionCoordinator | 10 |
| `RailMap/Map/MapLabelCollisionGrid.swift` | 64 | MapLabelCollisionGrid | 3 |
| `RailMap/Map/MapLabelStyle.swift` | 178 | MapLabelStyle, HaloLabel | 8 |
| `RailMap/Map/MapLayers.swift` | 102 | MapLayers | 1 |
| `RailMap/Map/MapLayersView.swift` | 180 | MapLayersView | 0 |
| `RailMap/Map/MapLineGeometry.swift` | 782 | RailNetworkStore.DrawnLine, LineBuild, FamilyRunBuild, PreparedFamilyRunBuild, PreparedLineBuild, ContinuousStrokeBuild, ChainPixelCache, JunctionCandidateIndex, MapLineGeometry | 23 |
| `RailMap/Map/MapNaming.swift` | 83 | MapNaming | 0 |
| `RailMap/Map/MapNetworkRendering.swift` | 560 | MapNetworkBuildState, MapNetworkGeometryCache, MapOverlayReconciliation, MapOverlayInstaller, MapGestureFrameProbe, MapGeometryFrame | 33 |
| `RailMap/Map/MapOverlayStyles.swift` | 292 | MapOverlayStyles | 16 |
| `RailMap/Map/MapPlaybackLayer.swift` | 606 | MapPlaybackLayer | 16 |
| `RailMap/Map/MapProjectedRailScene.swift` | 70 | MapProjectedRailScene | 1 |
| `RailMap/Map/MapProjection.swift` | 127 | MapProjection | 6 |
| `RailMap/Map/MapRailHomography.swift` | 66 | MapRailHomography | 3 |
| `RailMap/Map/MapRideMarkers.swift` | 539 | MapRideMarkers | 13 |
| `RailMap/Map/MapRideStationImportance.swift` | 80 | entry/support | 1 |
| `RailMap/Map/MapSelectedStationSnapshotController.swift` | 66 | MapSelectedStationSnapshotController | 5 |
| `RailMap/Map/MapStationLabelCoordinator.swift` | 110 | MapStationLabelCoordinator | 9 |
| `RailMap/Map/NetworkLOD.swift` | 172 | NetworkLOD, LODLine, LODBuild | 7 |
| `RailMap/Map/PlaybackAnnotations.swift` | 77 | PlaybackAnnotation, PlaybackAnnotationView | 1 |
| `RailMap/Map/RailMapController.swift` | 613 | RailMapController | 32 |
| `RailMap/Map/RailMapCoordinator.swift` | 4188 | RailMapView.Surface | 80 |
| `RailMap/Map/RailMapView.swift` | 506 | RailMapView | 6 |
| `RailMap/Map/RailwayLineCardView.swift` | 184 | RailwayLinePreview, RailwayLineCardView | 2 |
| `RailMap/Map/RideStationOverlay.swift` | 421 | RideStationOverlay, RideStationOverlayRenderer | 11 |
| `RailMap/Map/RideTapIndex.swift` | 266 | RideTapIndex, RideTapResolver.Bounds | 4 |
| `RailMap/Map/StationAnnotationViews.swift` | 305 | StationAnnotationView, RideStationAnnotationView | 10 |
| `RailMap/Map/StationAnnotations.swift` | 179 | StationAnnotation, RideStationAnnotation | 2 |
| `RailMap/Map/StationCardView.swift` | 461 | StationCard, StationCard, StationCardView, StationCardLineRow, StationShareRequest, StationActivitySheet, StationActivityItem | 9 |
| `RailMap/Playback/PlaybackController.swift` | 873 | PlaybackMapSnapshot, PlaybackMapRendering, PlaybackController | 28 |
| `RailMap/Playback/PlaybackTransportBar.swift` | 437 | PlaybackTransportBar, PlaybackHitProbe | 4 |
| `RailMap/Playback/PlaybackVideoExporter.swift` | 622 | PlaybackVideoExporter | 21 |
| `RailMap/Playback/VideoExportFlow.swift` | 91 | VideoExportFlow | 3 |
| `RailMap/Playback/VideoExportOptionsView.swift` | 155 | VideoExportOptionsView | 5 |
| `RailMap/Playback/VideoExportSettings.swift` | 188 | VideoExportSettings | 6 |
| `RailMap/Settings/DisplaySettings.swift` | 276 | DisplaySettings | 8 |
| `RailMap/Settings/SettingsView.swift` | 626 | SettingsView, DisplaySliderRow, SettingToggleRow | 3 |
| `RailMap/Sharing/JourneyShareImage.swift` | 436 | JourneyShareKind, JourneyPoster, JourneyShareView, JourneyActivitySheet, JourneyImageZoom, JourneyZoomScrollView | 11 |
| `RailMap/Sharing/ShareCardRendering.swift` | 424 | ShareCanvasGeometry, ShareCardRenderController, SharePNGWriter | 15 |
| `RailMap/Sharing/ShareComposerCanvas.swift` | 286 | ShareComposerCanvas, ShareComposerLiftedCard, ShareComposerCardImage, ShareComposerPlaceholder, ShareComposerWobble | 6 |
| `RailMap/Sharing/ShareComposerDrag.swift` | 227 | ShareComposerInteraction, ShareCardGestureEvent, ShareCardGestureLayer, ShareComposerFramePreferenceKey, ShareComposerCardFramePreferenceKey, ShareCanvasGeometry, ShareDragPlanner, ShareComposerModel | 10 |
| `RailMap/Sharing/ShareComposerModel.swift` | 653 | ShareCanvasRatio, ShareCanvasSize, GridSpan, GridRect, ShareMapArea, ShareCard, ShareLayout, ShareLayoutPreset, ShareComposerModel | 30 |
| `RailMap/Sharing/ShareComposerView.swift` | 913 | ShareComposerView | 26 |
| `RailMap/Sharing/StatisticsCardKind.swift` | 43 | StatisticsCardKind | 0 |
| `RailMap/Sharing/StatsWidgetGrid.swift` | 139 | StatsWidgetGridItem, StatsWidgetGrid, StatsWidgetSpanKey, View, StatsWidgetModuleLayout | 7 |
| `RailMap/Sharing/StatsWidgetShape.swift` | 65 | CardShape, CardSize, StatisticsCardKind | 1 |
| `RailMap/Sharing/StatsWidgetView.swift` | 343 | StatsWidgetRow, StatsWidgetColumn, StatsWidgetData, StatsWidgetView | 3 |
| `RailMap/Statistics/CategoryIndexes.swift` | 65 | CategoryIndexes | 1 |
| `RailMap/Statistics/MileageStatisticsStore.swift` | 990 | MileageStatisticsStore, Statistics.Train | 29 |
| `RailMap/Statistics/PassportCardStyle.swift` | 704 | PassportTone, View, PassportWidgetSurface, PassportInk, PassportInkKey, EnvironmentValues, PassportPosterKey, EnvironmentValues, CardSurface, PassportCardSurface, PassportEyebrow, PassportCardHeader, PassportCardHeader, PassportHeadline, View, PassportBlockSurface, PassportRule, PassportRow, PassportMetricGrid, PassportHighlight, PassportNote | 9 |
| `RailMap/Statistics/PassportStatistics.swift` | 389 | PassportStatistics | 10 |
| `RailMap/Statistics/PassportTicketFace.swift` | 923 | TicketFace, View, TicketDisplay, TicketField, TicketFaceCard | 28 |
| `RailMap/Statistics/PassportWorkspaceView.swift` | 225 | PassportWorkspaceView, PassportShareCard | 1 |
| `RailMap/Statistics/StatisticsArea.swift` | 284 | JapanAreaLeaf, StatisticsArea, StatisticsScope, JapanAreaGrid | 8 |
| `RailMap/Statistics/StatisticsComponents.swift` | 616 | View, StatisticsProgressSummary, StatisticsBar, StatisticsMetricRow, StatisticsColumnChart, StatisticsRankedRow, StatisticsRankedList, StatisticsSuperlative | 5 |
| `RailMap/Statistics/StatisticsDashboardContent.swift` | 1985 | StatisticsDashboardContent | 64 |
| `RailMap/Statistics/StatisticsFormatting.swift` | 107 | StatisticsFormat | 6 |
| `RailMap/Statistics/StatisticsScopePicker.swift` | 450 | StatisticsScopePicker, CalendarMonth, CalendarDayCell, AppLocalization | 9 |
| `RailMap/Statistics/StatisticsShareImage.swift` | 261 | StatisticsShareFile, StatisticsMapSnapshot, StatisticsShareView | 6 |
| `RailMap/Statistics/StatisticsYearBar.swift` | 55 | StatisticsYearBar | 2 |
| `RailMap/Statistics/TicketJimon.swift` | 275 | TicketJimon | 6 |
| `RailMap/Statistics/TicketPalette.swift` | 177 | TicketPalette | 4 |
| `RailMap/Timetable/ServicePatternPickerView.swift` | 694 | ServicePatternPickerView | 14 |
| `RailMap/Timetable/ServiceSectionSummary.swift` | 41 | ServiceSectionSummary | 1 |
| `RailMap/Timetable/TimetableQuickMatchController.swift` | 152 | TimetableQuickMatchController, TimetableQuickMatchLookup | 5 |
| `RailMap/Timetable/TimetableQuickMatchView.swift` | 81 | TimetableQuickMatchView | 0 |
| `RailMap/Timetable/TimetableTripDetailView.swift` | 201 | TimetableTripDetailView | 3 |
| `RailMap/Timetable/TrainResearchView.swift` | 252 | TrainResearchView | 5 |
| `RailMap/Workspace/AddDateAlert.swift` | 63 | AddDateAlert, View | 2 |
| `RailMap/Workspace/BottomChrome.swift` | 706 | BottomChromeMetrics, SheetLiveHeightKey, RailControlHeightKey, PanelHeader, SystemSheetTabSurface, View, RailSheetStageAction, RailSheetStageActionKey, EnvironmentValues, SheetStageActions, View, ResidentBottomSheetModifier, View | 20 |
| `RailMap/Workspace/JourneyEditorLaunch.swift` | 9 | JourneyEditorLaunch | 0 |
| `RailMap/Workspace/JourneyMenuTransition.swift` | 68 | JourneyMenuNamespaceKey, JourneyMenuSourceIsActiveKey, EnvironmentValues, JourneyMenuSource, JourneyMenuDestination, View | 4 |
| `RailMap/Workspace/JourneyWorkspaceStates.swift` | 85 | WorkspaceStatusView, WorkspaceUnavailableView | 0 |
| `RailMap/Workspace/ManualDates.swift` | 68 | ManualDates | 4 |
| `RailMap/Workspace/PanelMorph.swift` | 38 | PanelMorph, PanelStageReader | 1 |
| `RailMap/Workspace/PresentationHost.swift` | 74 | PresentationHost | 2 |
| `RailMap/Workspace/PrimaryTab.swift` | 66 | PrimaryTab | 0 |
| `RailMap/Workspace/RailWorkspaceView.swift` | 3366 | RailWorkspaceView, PanelCommandContext | 75 |
| `RailMap/Workspace/ResidentMapChrome.swift` | 121 | ResidentSheetMeasurements, ResidentMapChrome | 1 |
| `RailMap/Workspace/UtilityDestination.swift` | 112 | UtilityDestination, UtilityDestinationView | 0 |
| `RailMap/Workspace/WorkspaceDerived.swift` | 423 | ArrayGeneration, WorkspaceDerived | 13 |
| `RailMap/Workspace/WorkspaceLayout.swift` | 83 | PlaybackBarHeightKey, WorkspaceMenuMetrics, WorkspacePanelHeading, WorkspaceLayoutMetrics | 3 |
| `RailMap/Workspace/WorkspacePanelActions.swift` | 46 | WorkspacePanelActions | 0 |
| `RailMap/Workspace/WorkspacePanelPage.swift` | 227 | WorkspacePanelPage, WorkspacePanelViewport, SystemTabBarScrollClearance, SystemTabBarOcclusionReader, SystemTabBarContentEdge, TabHostTransparency | 16 |
| `RailMap/Workspace/WorkspacePresentations.swift` | 92 | WorkspaceDialog, WorkspacePresentations | 1 |
| `RailMap/Workspace/WorkspaceSheetContent.swift` | 196 | WorkspaceSheet, WorkspaceSheetContent | 0 |
| `RailMap/Workspace/WorkspaceTabs.swift` | 72 | WorkspaceTabs, WorkspacePage | 1 |
| `RailMap/Workspace/WorkspaceUtilityMenuItems.swift` | 32 | WorkspaceUtilityMenuItems | 0 |
| `RailMapUITests/AppTypographyPolicyTests.swift` | 51 | AppTypographyPolicyTests | 5 |
| `RailMapUITests/BasemapRenderingTests.swift` | 225 | BasemapRenderingTests | 9 |
| `RailMapUITests/ConsoleSweepTests.swift` | 389 | ConsoleSweepTests | 14 |
| `RailMapUITests/EditorLaunchSupport.swift` | 81 | EditorLaunchSupport | 6 |
| `RailMapUITests/IntegratedSharingUITests.swift` | 82 | IntegratedSharingUITests | 4 |
| `RailMapUITests/JourneyCompletionUITests.swift` | 256 | JourneyCompletionUITests | 7 |
| `RailMapUITests/JourneyGroupUITests.swift` | 115 | JourneyGroupUITests | 2 |
| `RailMapUITests/JourneySaveUITests.swift` | 381 | JourneySaveUITests | 16 |
| `RailMapUITests/JourneySharingUITests.swift` | 183 | JourneySharingUITests | 10 |
| `RailMapUITests/JourneyTranslationUITests.swift` | 300 | JourneyTranslationUITests | 16 |
| `RailMapUITests/LocalJourneyAutofillUITests.swift` | 265 | LocalJourneyAutofillUITests | 9 |
| `RailMapUITests/LongJourneyDetailUITests.swift` | 77 | LongJourneyDetailUITests | 7 |
| `RailMapUITests/MapCameraIntentTests.swift` | 238 | MapCameraIntentTests | 14 |
| `RailMapUITests/MapDetailLevelTests.swift` | 131 | MapDetailLevelTests | 9 |
| `RailMapUITests/MapIndependentRailPrototypeUITests.swift` | 162 | MapIndependentRailPrototypeUITests | 10 |
| `RailMapUITests/MapLargeDatasetTests.swift` | 222 | MapLargeDatasetTests, MapSampleUITestSupport | 9 |
| `RailMapUITests/MapLayerToggleTests.swift` | 594 | MapLayerToggleTests | 29 |
| `RailMapUITests/MapSnapshotCompositorFeasibilityTests.swift` | 289 | MapSnapshotCompositorFeasibilityTests | 9 |
| `RailMapUITests/MapZoomPerformanceTests.swift` | 331 | MapZoomPerformanceTests, MapZoomPerformanceTests | 16 |
| `RailMapUITests/NewTripUITests.swift` | 605 | NewTripUITests | 31 |
| `RailMapUITests/OrdinaryPhysicalRouteUITests.swift` | 692 | OrdinaryPhysicalRouteUITests | 22 |
| `RailMapUITests/PlaybackLayoutTests.swift` | 249 | PlaybackLayoutTests | 15 |
| `RailMapUITests/PlaybackVideoExportTests.swift` | 204 | PlaybackVideoExportTests | 9 |
| `RailMapUITests/RailMapUITests.swift` | 898 | RailMapUITests, TransferGuideImportUITests | 38 |
| `RailMapUITests/RailwayRouteEntryUITests.swift` | 155 | RailwayRouteEntryUITests | 9 |
| `RailMapUITests/RefactorReleaseMemoryUITests.swift` | 209 | RefactorReleaseMemoryUITests | 6 |
| `RailMapUITests/RouteStressTests.swift` | 156 | RouteStressTests | 9 |
| `RailMapUITests/ShareComposerMatrixTests.swift` | 361 | ShareComposerMatrixTests | 20 |
| `RailMapUITests/StationPresentationTests.swift` | 222 | StationPresentationTests | 9 |
| `RailMapUITests/StatisticsCalendarUITests.swift` | 108 | StatisticsCalendarUITests | 3 |
| `RailMapUITests/StatisticsRhythmYearUITests.swift` | 63 | StatisticsRhythmYearUITests | 4 |
| `RailMapUITests/StopDateTimeUITests.swift` | 65 | StopDateTimeUITests | 2 |
| `RailMapUITests/ThroughServiceUITests.swift` | 330 | ThroughServiceUITests | 14 |
| `RailMapUITests/TimetableCoverageUITests.swift` | 43 | TimetableCoverageUITests | 2 |
| `RailMapUITests/TimetableDiscoveryUITests.swift` | 219 | TimetableDiscoveryUITests, NewTripTimetableTestSupport | 12 |
| `RailMapUITests/TimetableQuickMatchUITests.swift` | 87 | TimetableQuickMatchUITests | 5 |
| `RailMapUITests/TimetableSymbolUITests.swift` | 79 | TimetableSymbolUITests | 3 |
| `RailMapUITests/TrainServicePatternUITests.swift` | 311 | TrainServicePatternUITests | 13 |
| `RailMapUITests/TrainTimetableUsabilityUITests.swift` | 72 | TrainTimetableUsabilityUITests | 3 |
| `RailMapUITests/WorkspaceEditingTests.swift` | 955 | WorkspaceEditingTests, EditorUITestSupport | 32 |
| `auxiliary/RailAlignmentInspector/InspectionKit/Package.swift` | 12 | entry/support | 0 |
| `auxiliary/RailAlignmentInspector/InspectionKit/Sources/RailInspection/BatchInspection.swift` | 254 | BatchInspectionCoordinateIdentity, BatchInspectionIdentity, BatchInspectionGeometryStatus, BatchInspectionViewpoint, BatchInspectionItem, BatchInspectionPlan, BatchCaptureStatus, BatchInspectionProgress, BatchInspectionCheckpoint, BatchGeometry | 10 |
| `auxiliary/RailAlignmentInspector/InspectionKit/Sources/RailInspection/Inspection.swift` | 245 | InspectionPoint, InspectionInput, InspectionItem, InspectionPlan, ReviewVerdict, InspectionReview, GeometryScan | 5 |
| `auxiliary/RailAlignmentInspector/InspectionKit/Tests/RailInspectionTests/BatchInspectionTests.swift` | 117 | entry/support | 8 |
| `auxiliary/RailAlignmentInspector/InspectionKit/Tests/RailInspectionTests/InspectionTests.swift` | 128 | entry/support | 12 |
| `auxiliary/RailAlignmentInspector/Sources/BatchCaptureController.swift` | 445 | BatchCaptureController | 17 |
| `auxiliary/RailAlignmentInspector/Sources/BatchCaptureGeometry.swift` | 210 | BatchCaptureGeometry | 11 |
| `auxiliary/RailAlignmentInspector/Sources/InspectionEvidence.swift` | 166 | ReferenceTrack, EvidenceError, EvidenceBundle, InspectionDistances | 5 |
| `auxiliary/RailAlignmentInspector/Sources/InspectionViewpoints.swift` | 39 | InspectionViewpoints | 1 |
| `auxiliary/RailAlignmentInspector/Sources/InspectorApp.swift` | 239 | InspectorApp, ViewRecord, InspectorView, EvidenceDocument | 2 |
| `auxiliary/RailAlignmentInspector/Sources/InspectorMap.swift` | 167 | InspectorMap | 8 |
| `auxiliary/RailAlignmentInspector/Sources/InspectorModel.swift` | 475 | ComparisonMode, InspectorModel, Coordinate, Array | 30 |
| `auxiliary/RailAlignmentInspector/Sources/InspectorStrokeGeometry.swift` | 91 | InspectorStrokeGeometry | 3 |
| `auxiliary/RouteWorkbench/App/RouteWorkbenchModel.swift` | 451 | RouteWorkbenchModel | 13 |
| `auxiliary/RouteWorkbench/App/RouteWorkbenchView.swift` | 249 | RouteWorkbenchView, RouteWorkbenchDocument | 4 |
| `auxiliary/ThroughWorkbench/App/InspectionPlanView.swift` | 164 | InspectionPlanView | 3 |
| `auxiliary/ThroughWorkbench/App/PatchEditorView.swift` | 62 | PatchEditorView | 0 |
| `auxiliary/ThroughWorkbench/App/PatternDetailView.swift` | 103 | PatternDetailView, CorridorMap | 1 |
| `auxiliary/ThroughWorkbench/App/ThroughWorkbenchApp.swift` | 13 | ThroughWorkbenchApp | 0 |
| `auxiliary/ThroughWorkbench/App/WorkbenchSession.swift` | 168 | ImportKind, ExportKind, WorkbenchSnapshot, SessionError | 10 |
| `auxiliary/ThroughWorkbench/App/WorkbenchStore.swift` | 140 | WorkbenchStore, PatchDraft | 8 |
| `auxiliary/ThroughWorkbench/App/WorkbenchView.swift` | 210 | WorkbenchJSONDocument, WorkbenchView, ReviewOverviewView, IssueRow | 3 |
| `auxiliary/ThroughWorkbench/WorkbenchCore/Package.swift` | 5 | entry/support | 0 |
| `auxiliary/ThroughWorkbench/WorkbenchCore/Sources/WorkbenchCore/InspectionPlan.swift` | 456 | InspectionPlan, InspectionCheck, InspectionFinding, WorkbenchDocument, InspectionWorker | 17 |
| `auxiliary/ThroughWorkbench/WorkbenchCore/Sources/WorkbenchCore/JSONValue.swift` | 70 | JSONValue, WorkbenchError, ISODay | 6 |
| `auxiliary/ThroughWorkbench/WorkbenchCore/Sources/WorkbenchCore/NetworkReview.swift` | 441 | Severity, ReviewIssue, PatternDifference, PatternSummary, LegSummary, WorkbenchDocument | 18 |
| `auxiliary/ThroughWorkbench/WorkbenchCore/Sources/WorkbenchCore/ReviewedOnsets.swift` | 12 | WorkbenchDocument | 1 |
| `auxiliary/ThroughWorkbench/WorkbenchCore/Sources/WorkbenchCore/TemporalDocument.swift` | 213 | LegPatch, TemporalPatch, WorkbenchDocument | 7 |
| `auxiliary/ThroughWorkbench/WorkbenchCore/Tests/WorkbenchCoreTests/InspectionPlanTests.swift` | 343 | InspectionPlanTests | 28 |
| `auxiliary/ThroughWorkbench/WorkbenchCore/Tests/WorkbenchCoreTests/TemporalDocumentTests.swift` | 135 | TemporalDocumentTests | 12 |
