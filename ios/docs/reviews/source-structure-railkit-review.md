# RailKit source structure review — 2026-10-10

## Scope and evidence

The initial inventory contained 120 production Swift files under `ios/RailKit/Sources`: 85 RailCore, 30 RailPresentation, and 5 RailApplication files. Every file was included in a declaration/section-marker/comment-reference pass. Focused body/dependency review covered the concrete extractions and comment findings below; this was an organization audit, not a full logic or runtime correctness audit. Four extractions bring the production inventory to 124 files. The full filename mapping below also records which files were included in the structure pass.

Read repository `AGENTS.md`, `ios/AGENTS.md`, and the current section of `ios/VERIFICATION.md`. No builds, tests, retired runners, resource regeneration, or external actions were run. Preserve each SwiftPM module and its existing Resources directory; recursive source discovery accepts feature subdirectories without changing public symbols.

## Completed self-contained extractions

Declarations, access levels, and code bodies remain unchanged. Added imports match the original source. Each of the eight extracted public declarations occurs exactly once in the current sources.

| Original source | Destination | Extracted declarations | Dependency boundary |
|---|---|---|---|
| RailCore/Editor/EditorTime.swift, original line 252 onward | RailCore/Editor/EditorAIEligibility.swift | EditorAIDenial, EditorAIStop, EditorAIEligibility | Foundation UUID and public EditorTimeInput; private confirmedInvalid remains inside EditorAIEligibility |
| RailPresentation/Regions/RegionClock.swift, original line 283 onward | RailPresentation/Regions/JourneyClock.swift | JourneyClock and its attached documentation | Public RegionClock API; its private readingKey remains inside JourneyClock; RegionClock private initializer is not used |
| RailPresentation/Editing/JourneyDraftSelection.swift, original lines 78–134 | RailPresentation/Editing/JourneyDraftEdits.swift | JourneyDraftDeletion, JourneyDraftEdits | Public JourneyDraftStop, Foundation IndexSet/UUID; no private reducer helper dependency |
| RailPresentation/Editing/JourneyDraftSelection.swift, original line 417 onward | RailPresentation/Editing/CatalogLinePreferenceMapping.swift | CatalogLinePreference, CatalogLinePreferenceMapping | Public RailCore EditorCatalog and catalog row types; no JourneyDraftSelection private helper dependency |

The owning chat applied these feature directory moves. EditorAIEligibility is in Editor; JourneyClock is in Regions; the draft/catalog files are in Editing.

## Corrected stale comments

- ContinuousStroke.drawnDecimationTolerance documentation, original line 99: removed the claim that retired `ios/verify.sh` enforces agreement between the three renderer constants. The tolerance and counterpart references remain; documentation now instructs reviewers to check them.
- RouteNetwork documentation in RouteFeature.swift, original line 146: replaced “displayPartsForLine … is not ported yet” with the existing DisplayParts implementation.
- JourneyClock.rideMinutes documentation: replaced the retired North American service example with the same generic origin/destination clock explanation. No clock support or behavior changed.

## Filename improvements for the owning chat

- `Import.swift` → `ImportEngine.swift`: the top-level owner is ImportEngine, and the file contains its progressive session and sample-manifest rules.
- `RouteFeature.swift` → `RouteNetwork.swift`: RouteNetwork owns most of this 974-line file; RouteFeature is a small input DTO near its beginning. A later extraction of the route DTOs would make the names even clearer, but is not necessary for the directory move.
- `RegionScope.swift` → `RegionScopeRule.swift`: matches its only top-level public owner.
- `StationLineSelection.swift` → `JourneyDraftSelection.swift`: after the completed extractions, its remaining primary responsibility is JourneyDraftSelection plus its event/result/stop model.

Keep existing domain names such as RouteSolver, OverlapLanes, ContinuousStroke and Statistics. A filename change does not justify changing public type or function names.

## Additional safe extraction options, not implemented

- Train.swift: whole top-level RouteConfirmation, TrainStore, Train, Stop, RouteSection, RoutePolicy and TrainStyle declarations may each move with their own CodingKeys and methods. Their calls to TrainValidation and StationCodeAliases are module-visible/public; no unrelated file-private function was found in these declarations. Separate TrainValidation into TrainValidation.swift only by keeping its existing extensions and dynamic JSON helpers together. Do not split its private validator/normalizer helpers across files.
- RouteFeature.swift: complete top-level RouteGeometry, RouteHints, RouteFeature, CanonicalRoute and RouteProjectionCache declarations may move as DTOs, preserving existing module-internal members. RouteProjectionCache.storage depends on public RouteNetwork.Projection; it is internal, not fileprivate. Keep RouteNetwork's private canonicalization/slicing helpers together.
- RailHistory.swift: whole RailHistoryRevisionSet, RailPrecomputedSolverContext, RailPrecomputedRouteGate and RailServiceValidity declarations are self-contained. Their private CodingKeys belong to the moved declaration. RailPrecomputedRouteGate calls public RailHistoryRevisionSet fields. RailHistoryOverlay has internal Match.allows and its own validation methods; review those callers before considering a further overlay split.
- RouteGraph.swift: the complete `extension RouteGraph` containing GraphCachePolicy + RouteGraphStore (original lines 2590–3039) can move together into RouteGraphStore.swift: its outer dependencies CompiledSections, JunctionPlan and spatial/key utilities are module-internal/public. Preserve the class's private cache fields and methods. The complete SectionFeatureCollection extension plus SectionFeature Decodable extension (original lines 3076 onward) can move together into RouteGraphDecoding.swift; nested private Properties/Geometry/CodingKeys stay with their decoder and their other dependencies are public/internal. Do not move partial decoder helpers.
- CompactPackage.swift: all Headers-related extensions (original lines 304–447), including CompactPackage.headers and CompactPackage.Line.header, form one self-contained CompactPackageHeaders.swift file. Its private truthy decoder remains in the Headers.Line declaration. The complete StationDirectory extension (original lines 449 onward) forms CompactPackageStationDirectory.swift. Do not share the two private truthy helpers by widening their visibility; their CodingKeys types differ.

## Function organization without access changes

RouteSolver (4,185 lines at initial inventory) and RouteGraph (3,206 lines) have coherent helper clusters but no navigable MARK hierarchy. Prefer adding section markers at the existing responsibility boundaries rather than relocating individual private helpers.

Suggested RouteSolver anchors: policy/context types; edgeHasPreferredInstitution (station candidate filtering); addStationTransferConnectorEdges (platform connectors); inferSectionRouteConstraints (section hints/attempts); SolvedSection and physicalContinuationPath (physical continuation proofs); StationSectionInference (station-run inference); verifiedSourcePath (source path proofs); OfficialIntervalIndex (official interval resolution); PreparedSectionEndpoints/solveSection (section solve); completeRouteEndpointCoordinates (endpoint/edge constraints); dijkstra (path search); sectionEndpointBBox (shared private geometry and key helpers). Preserve helper adjacency and order.

Suggested RouteGraph anchors: BuildPolicy/TrackIdentity/PhysicalJunction (physical identity); RouteSection/templateKey/CacheKeyTrain (cache identities); SolveContext (dated solve context); SectionProperties through Graph (graph model and lazy indexes); build/CompiledSections (compiled graph construction); JunctionPlan/addPhysicalJunctions (junction installation and identity windows); graphGridKey through pathTouchesRegionEdge (spatial queries); RouteGraphStore (cache owner); jsSorted/orderedUnique (JavaScript key ordering); SectionFeatureCollection/Decodable (dataset decoding).

TrainTimetableDatabase (1,468 lines) likewise benefits from markers around schema/init/open ownership, station/service/trip lookups, trip matching, and SQL binding/statement lifetime helpers. Keep its statement/connection private members in the class. JourneyCompletion already groups prompt DTOs, response DTOs and validation/merge helpers; its private extensions cannot simply be relocated into separate files without losing lexical private access. Localization has fileprivate JSStringKey/utf16Equal and private state; OperatorBranding has private CodeUnitTable/CodeUnitSet/JSText; StationDisplay has private Cell and private top-level string helpers; EditorCatalog has private builder accumulator/identity/match helpers. Their function sets are not safe mechanical cross-file extractions. Existing sections should be retained; do not widen access solely to reduce line counts.

## Historical evidence comments

CompactPackage.Headers records decode benchmarks for CA/US alongside JP and names the retired bench tool; ContinuousStroke records historical US/CA geometry measurements. These are historical provenance, not active data support or current performance evidence. If retained, label them explicitly as historical. Do not rerun or recreate the retired tool. Counts of committed itineraries/features and source schema references throughout the older port headers were not independently remeasured; they should not be presented as fresh measurements by the cleanup.

## Complete directory move map

This map covers every current production Swift file exactly once. The owning chat applied the feature moves and the four suggested filename improvements. All source paths are relative to `ios/RailKit/Sources`. RailCore uses 12 feature groups, RailPresentation uses 7, and RailApplication groups its five thin adapters by their consuming feature. Rendering includes the pure playback geometry/camera compiler. Identity includes operator/service branding and localized names. Utilities contains the shared coordinate/date/JavaScript primitive operations.

### RailCore

| Current filename | Feature subdirectory | Destination |
|---|---|---|
| CanonicalTrainStoreJSON.swift | Journeys | RailCore/Journeys/CanonicalTrainStoreJSON.swift |
| JourneyEnglishName.swift | Journeys | RailCore/Journeys/JourneyEnglishName.swift |
| JourneyGroup.swift | Journeys | RailCore/Journeys/JourneyGroup.swift |
| ServiceCaption.swift | Journeys | RailCore/Journeys/ServiceCaption.swift |
| StoreOperations.swift | Journeys | RailCore/Journeys/StoreOperations.swift |
| Train.swift | Journeys | RailCore/Journeys/Train.swift |
| EditorAIEligibility.swift | Editor | RailCore/Editor/EditorAIEligibility.swift |
| EditorCatalog.swift | Editor | RailCore/Editor/EditorCatalog.swift |
| EditorTime.swift | Editor | RailCore/Editor/EditorTime.swift |
| LocalJourneyAutofill.swift | Editor | RailCore/Editor/LocalJourneyAutofill.swift |
| RailwayRouteEditing.swift | Editor | RailCore/Editor/RailwayRouteEditing.swift |
| RouteSectionServiceEditing.swift | Editor | RailCore/Editor/RouteSectionServiceEditing.swift |
| ChatGPTSubscriptionProtocol.swift | Import | RailCore/Import/ChatGPTSubscriptionProtocol.swift |
| Import.swift | Import | RailCore/Import/ImportEngine.swift |
| JREastGuide.swift | Import | RailCore/Import/JREastGuide.swift |
| JourneyCompletion.swift | Import | RailCore/Import/JourneyCompletion.swift |
| JourneyTextImport.swift | Import | RailCore/Import/JourneyTextImport.swift |
| TransferGuide.swift | Import | RailCore/Import/TransferGuide.swift |
| TransferGuideText.swift | Import | RailCore/Import/TransferGuideText.swift |
| TransferGuideTrains.swift | Import | RailCore/Import/TransferGuideTrains.swift |
| LocalJourneySearch.swift | Routing | RailCore/Routing/LocalJourneySearch.swift |
| PhysicalRouteMatcher.swift | Routing | RailCore/Routing/PhysicalRouteMatcher.swift |
| PrecomputedRouteDisplay.swift | Routing | RailCore/Routing/PrecomputedRouteDisplay.swift |
| RailwayDirection.swift | Routing | RailCore/Routing/RailwayDirection.swift |
| RailwayRouteChoices.swift | Routing | RailCore/Routing/RailwayRouteChoices.swift |
| RailwayRouteInference.swift | Routing | RailCore/Routing/RailwayRouteInference.swift |
| ResolvedRailRoute.swift | Routing | RailCore/Routing/ResolvedRailRoute.swift |
| ResolvedRouteExport.swift | Routing | RailCore/Routing/ResolvedRouteExport.swift |
| RouteBatchInspection.swift | Routing | RailCore/Routing/RouteBatchInspection.swift |
| RouteConfirmationRepair.swift | Routing | RailCore/Routing/RouteConfirmationRepair.swift |
| RouteFeature.swift | Routing | RailCore/Routing/RouteNetwork.swift |
| RouteGraph.swift | Routing | RailCore/Routing/RouteGraph.swift |
| RouteRepair.swift | Routing | RailCore/Routing/RouteRepair.swift |
| RouteResolutionMemo.swift | Routing | RailCore/Routing/RouteResolutionMemo.swift |
| RouteSolveLimiter.swift | Routing | RailCore/Routing/RouteSolveLimiter.swift |
| RouteSolver.swift | Routing | RailCore/Routing/RouteSolver.swift |
| SharedRouteWork.swift | Routing | RailCore/Routing/SharedRouteWork.swift |
| StationIntervalResolver.swift | Routing | RailCore/Routing/StationIntervalResolver.swift |
| TokyoConventionalRouteInference.swift | Routing | RailCore/Routing/TokyoConventionalRouteInference.swift |
| TravelDirection.swift | Routing | RailCore/Routing/TravelDirection.swift |
| TripConnectivity.swift | Routing | RailCore/Routing/TripConnectivity.swift |
| TripRoutePlanner.swift | Routing | RailCore/Routing/TripRoutePlanner.swift |
| RailIntervalCodes.swift | Stations | RailCore/Stations/RailIntervalCodes.swift |
| StationCodeAliases.swift | Stations | RailCore/Stations/StationCodeAliases.swift |
| StationIndex.swift | Stations | RailCore/Stations/StationIndex.swift |
| StationRouteEligibility.swift | Stations | RailCore/Stations/StationRouteEligibility.swift |
| Stations.swift | Stations | RailCore/Stations/Stations.swift |
| JapanThroughServices.swift | Timetable | RailCore/Timetable/JapanThroughServices.swift |
| LineServiceCatalog.swift | Timetable | RailCore/Timetable/LineServiceCatalog.swift |
| TimetablePhysicalRouteMatch.swift | Timetable | RailCore/Timetable/TimetablePhysicalRouteMatch.swift |
| TimetableSearch.swift | Timetable | RailCore/Timetable/TimetableSearch.swift |
| TimetableServiceDayContext.swift | Timetable | RailCore/Timetable/TimetableServiceDayContext.swift |
| TimetableTripMatch.swift | Timetable | RailCore/Timetable/TimetableTripMatch.swift |
| TrainServicePatterns.swift | Timetable | RailCore/Timetable/TrainServicePatterns.swift |
| TrainTimetableDatabase.swift | Timetable | RailCore/Timetable/TrainTimetableDatabase.swift |
| PhysicalRailJunctionRegistry.swift | History | RailCore/History/PhysicalRailJunctionRegistry.swift |
| RailHistory.swift | History | RailCore/History/RailHistory.swift |
| RailHistoryStations.swift | History | RailCore/History/RailHistoryStations.swift |
| ContinuousStroke.swift | Rendering | RailCore/Rendering/ContinuousStroke.swift |
| DisplayParts.swift | Rendering | RailCore/Rendering/DisplayParts.swift |
| Grooming.swift | Rendering | RailCore/Rendering/Grooming.swift |
| LaneLOD.swift | Rendering | RailCore/Rendering/LaneLOD.swift |
| OverlapLanes.swift | Rendering | RailCore/Rendering/OverlapLanes.swift |
| Playback.swift | Rendering | RailCore/Rendering/Playback.swift |
| RideMarkerVisibility.swift | Rendering | RailCore/Rendering/RideMarkerVisibility.swift |
| StationDisplay.swift | Rendering | RailCore/Rendering/StationDisplay.swift |
| StationJoinSmoothing.swift | Rendering | RailCore/Rendering/StationJoinSmoothing.swift |
| StationVisibility.swift | Rendering | RailCore/Rendering/StationVisibility.swift |
| StrokeRide.swift | Rendering | RailCore/Rendering/StrokeRide.swift |
| Visibility.swift | Rendering | RailCore/Rendering/Visibility.swift |
| Statistics.swift | Statistics | RailCore/Statistics/Statistics.swift |
| Localization.swift | Identity | RailCore/Identity/Localization.swift |
| OperatorBranding.swift | Identity | RailCore/Identity/OperatorBranding.swift |
| OperatorIdentity.swift | Identity | RailCore/Identity/OperatorIdentity.swift |
| TrainServiceBranding.swift | Identity | RailCore/Identity/TrainServiceBranding.swift |
| CompactPackage.swift | Data | RailCore/Data/CompactPackage.swift |
| DatasetManifestIndex.swift | Data | RailCore/Data/DatasetManifestIndex.swift |
| DisplayChunkReader.swift | Data | RailCore/Data/DisplayChunkReader.swift |
| RailResourceRevisions.swift | Data | RailCore/Data/RailResourceRevisions.swift |
| Coordinates.swift | Utilities | RailCore/Utilities/Coordinates.swift |
| Dates.swift | Utilities | RailCore/Utilities/Dates.swift |
| Geometry.swift | Utilities | RailCore/Utilities/Geometry.swift |
| JSMath.swift | Utilities | RailCore/Utilities/JSMath.swift |
| JSNumber.swift | Utilities | RailCore/Utilities/JSNumber.swift |
| JSString.swift | Utilities | RailCore/Utilities/JSString.swift |
| SearchFold.swift | Utilities | RailCore/Utilities/SearchFold.swift |

### RailPresentation

| Current filename | Feature subdirectory | Destination |
|---|---|---|
| JourneyDetailSnapshot.swift | Journeys | RailPresentation/Journeys/JourneyDetailSnapshot.swift |
| JourneyHeroIdentity.swift | Journeys | RailPresentation/Journeys/JourneyHeroIdentity.swift |
| JourneyPresentation.swift | Journeys | RailPresentation/Journeys/JourneyPresentation.swift |
| JourneyPresentationResolver.swift | Journeys | RailPresentation/Journeys/JourneyPresentationResolver.swift |
| JourneyRouteIdentity.swift | Journeys | RailPresentation/Journeys/JourneyRouteIdentity.swift |
| JourneySearchMatcher.swift | Journeys | RailPresentation/Journeys/JourneySearchMatcher.swift |
| JourneyServiceSections.swift | Journeys | RailPresentation/Journeys/JourneyServiceSections.swift |
| JourneyTitle.swift | Journeys | RailPresentation/Journeys/JourneyTitle.swift |
| LaunchJourneySelector.swift | Journeys | RailPresentation/Journeys/LaunchJourneySelector.swift |
| RideLedger.swift | Journeys | RailPresentation/Journeys/RideLedger.swift |
| RouteStatusResolver.swift | Journeys | RailPresentation/Journeys/RouteStatusResolver.swift |
| CatalogLinePreferenceMapping.swift | Editing | RailPresentation/Editing/CatalogLinePreferenceMapping.swift |
| DraftMapSnapshot.swift | Editing | RailPresentation/Editing/DraftMapSnapshot.swift |
| JourneyDraftEdits.swift | Editing | RailPresentation/Editing/JourneyDraftEdits.swift |
| StationLineSelection.swift | Editing | RailPresentation/Editing/JourneyDraftSelection.swift |
| DisplayNetworkEra.swift | Map | RailPresentation/Map/DisplayNetworkEra.swift |
| LongitudeArc.swift | Map | RailPresentation/Map/LongitudeArc.swift |
| MapCameraPolicy.swift | Map | RailPresentation/Map/MapCameraPolicy.swift |
| MapRebuildPolicy.swift | Map | RailPresentation/Map/MapRebuildPolicy.swift |
| MapUpdatePlan.swift | Map | RailPresentation/Map/MapUpdatePlan.swift |
| NetworkVisibilityPolicy.swift | Map | RailPresentation/Map/NetworkVisibilityPolicy.swift |
| RideTapResolver.swift | Map | RailPresentation/Map/RideTapResolver.swift |
| StationLabelVisibility.swift | Stations | RailPresentation/Stations/StationLabelVisibility.swift |
| StationPlaceLink.swift | Stations | RailPresentation/Stations/StationPlaceLink.swift |
| StatisticsDateSelection.swift | Statistics | RailPresentation/Statistics/StatisticsDateSelection.swift |
| StatisticsLineCoverage.swift | Statistics | RailPresentation/Statistics/StatisticsLineCoverage.swift |
| JourneyClock.swift | Regions | RailPresentation/Regions/JourneyClock.swift |
| RegionClock.swift | Regions | RailPresentation/Regions/RegionClock.swift |
| RegionScope.swift | Regions | RailPresentation/Regions/RegionScopeRule.swift |
| PanelDetentResolver.swift | Workspace | RailPresentation/Workspace/PanelDetentResolver.swift |
| PickDuringRunRule.swift | Workspace | RailPresentation/Workspace/PickDuringRunRule.swift |
| WorkspaceJourneyRules.swift | Workspace | RailPresentation/Workspace/WorkspaceJourneyRules.swift |
| WorkspaceLayoutPolicy.swift | Workspace | RailPresentation/Workspace/WorkspaceLayoutPolicy.swift |

### RailApplication

| Current filename | Feature subdirectory | Destination |
|---|---|---|
| ImportPreflight.swift | Import | RailApplication/Import/ImportPreflight.swift |
| ImportStaging.swift | Import | RailApplication/Import/ImportStaging.swift |
| RideDraftValidation.swift | Editor | RailApplication/Editor/RideDraftValidation.swift |
| TripRouteValidation.swift | Routing | RailApplication/Routing/TripRouteValidation.swift |
| MileageMatching.swift | Statistics | RailApplication/Statistics/MileageMatching.swift |

## Evidence/result note

Scope: declaration/file organization and specific stale comments in all RailKit production source filenames. Result: four self-contained extractions and three narrow comment corrections; complete directory map checked against the recursive source inventory. No measured runtime, performance, pixel, or build claim. Compilation remains for the owning chat only if a focused correctness question requires it. Existing user changes and Resources are preserved.
