PRAGMA foreign_keys = ON;

CREATE TABLE metadata (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL
);

CREATE TABLE operators (
    operator_id TEXT PRIMARY KEY NOT NULL,
    legal_name TEXT NOT NULL,
    display_name TEXT NOT NULL,
    operator_type TEXT NOT NULL,
    valid_from TEXT NOT NULL,
    valid_until TEXT,
    predecessor_operator_id TEXT REFERENCES operators(operator_id) DEFERRABLE INITIALLY DEFERRED,
    successor_operator_id TEXT REFERENCES operators(operator_id) DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE services (
    service_id TEXT PRIMARY KEY NOT NULL,
    canonical_name TEXT NOT NULL,
    service_class TEXT NOT NULL,
    historical_generation INTEGER NOT NULL CHECK (historical_generation > 0),
    first_verified_date TEXT,
    last_verified_date TEXT,
    jr_scope TEXT NOT NULL CHECK (jr_scope IN ('jr', 'jr_ancestral', 'through_jr', 'private')),
    successor_region TEXT,
    successor_operator_id TEXT REFERENCES operators(operator_id)
);

CREATE TABLE source_documents (
    source_id TEXT PRIMARY KEY NOT NULL,
    publisher TEXT NOT NULL,
    title TEXT NOT NULL,
    source_type TEXT NOT NULL,
    url_or_locator TEXT NOT NULL,
    issue TEXT,
    publication_date TEXT,
    effective_date TEXT,
    accessed_at TEXT NOT NULL,
    content_hash TEXT,
    license_status TEXT NOT NULL,
    redistribution_status TEXT NOT NULL,
    automated_extraction_allowed INTEGER NOT NULL CHECK (automated_extraction_allowed IN (0, 1)),
    archive_locator TEXT,
    notes TEXT
);

CREATE TABLE service_name_periods (
    service_id TEXT NOT NULL REFERENCES services(service_id),
    name TEXT NOT NULL,
    language TEXT NOT NULL,
    valid_from TEXT NOT NULL,
    valid_until TEXT,
    name_type TEXT NOT NULL,
    source_id TEXT NOT NULL REFERENCES source_documents(source_id),
    PRIMARY KEY (service_id, language, name_type, valid_from, name)
);

CREATE TABLE timetable_versions (
    timetable_version_id TEXT PRIMARY KEY NOT NULL,
    operator_scope TEXT NOT NULL,
    effective_from TEXT NOT NULL,
    effective_until TEXT NOT NULL,
    edition_name TEXT NOT NULL,
    revision_type TEXT NOT NULL,
    publication_date TEXT,
    completeness TEXT NOT NULL CHECK (completeness IN ('verified', 'partial', 'unknown', 'conflict'))
);

CREATE TABLE timetable_version_sources (
    timetable_version_id TEXT NOT NULL REFERENCES timetable_versions(timetable_version_id),
    source_id TEXT NOT NULL REFERENCES source_documents(source_id),
    PRIMARY KEY (timetable_version_id, source_id)
);

CREATE TABLE holiday_calendar_years (
    year INTEGER PRIMARY KEY NOT NULL CHECK (year BETWEEN 1912 AND 9999),
    status TEXT NOT NULL CHECK (status IN ('verified', 'partial', 'missing', 'conflict')),
    source_id TEXT REFERENCES source_documents(source_id),
    notes TEXT
);

CREATE TABLE holiday_dates (
    service_date TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    source_id TEXT NOT NULL REFERENCES source_documents(source_id)
);

CREATE TABLE calendars (
    calendar_id TEXT PRIMARY KEY NOT NULL,
    monday INTEGER NOT NULL CHECK (monday IN (0, 1)),
    tuesday INTEGER NOT NULL CHECK (tuesday IN (0, 1)),
    wednesday INTEGER NOT NULL CHECK (wednesday IN (0, 1)),
    thursday INTEGER NOT NULL CHECK (thursday IN (0, 1)),
    friday INTEGER NOT NULL CHECK (friday IN (0, 1)),
    saturday INTEGER NOT NULL CHECK (saturday IN (0, 1)),
    sunday INTEGER NOT NULL CHECK (sunday IN (0, 1)),
    valid_from TEXT NOT NULL,
    valid_until TEXT NOT NULL,
    holiday_policy TEXT NOT NULL CHECK (holiday_policy IN ('none', 'treat_as_sunday'))
);

CREATE TABLE calendar_exceptions (
    calendar_id TEXT NOT NULL REFERENCES calendars(calendar_id),
    service_date TEXT NOT NULL,
    exception_type TEXT NOT NULL CHECK (exception_type IN ('add', 'remove')),
    reason TEXT,
    source_id TEXT NOT NULL REFERENCES source_documents(source_id),
    PRIMARY KEY (calendar_id, service_date)
);

CREATE TABLE station_identities (
    station_id TEXT PRIMARY KEY NOT NULL,
    name_snapshot TEXT NOT NULL,
    reference_kind TEXT NOT NULL CHECK (reference_kind IN ('current_n02', 'historical_overlay')),
    current_source_code TEXT,
    rail_history_id TEXT,
    valid_from TEXT,
    valid_until TEXT,
    CHECK (
        (reference_kind = 'current_n02' AND current_source_code IS NOT NULL AND rail_history_id IS NULL)
        OR
        (reference_kind = 'historical_overlay' AND rail_history_id IS NOT NULL AND current_source_code IS NULL)
    )
);

CREATE TABLE trips (
    trip_id TEXT PRIMARY KEY NOT NULL,
    timetable_version_id TEXT NOT NULL REFERENCES timetable_versions(timetable_version_id),
    service_id TEXT NOT NULL REFERENCES services(service_id),
    calendar_id TEXT NOT NULL REFERENCES calendars(calendar_id),
    train_number TEXT,
    public_number TEXT,
    origin_station_id TEXT NOT NULL REFERENCES station_identities(station_id),
    destination_station_id TEXT NOT NULL REFERENCES station_identities(station_id),
    direction TEXT,
    service_class TEXT NOT NULL,
    operation_group_id TEXT,
    notes TEXT
);

CREATE TABLE stop_times (
    trip_id TEXT NOT NULL REFERENCES trips(trip_id) ON DELETE CASCADE,
    stop_sequence INTEGER NOT NULL CHECK (stop_sequence >= 0),
    station_id TEXT NOT NULL REFERENCES station_identities(station_id),
    arrival_time TEXT,
    departure_time TEXT,
    arrival_seconds INTEGER CHECK (arrival_seconds IS NULL OR arrival_seconds >= 0),
    departure_seconds INTEGER CHECK (departure_seconds IS NULL OR departure_seconds >= 0),
    day_offset INTEGER NOT NULL DEFAULT 0 CHECK (day_offset >= 0),
    arrival_day_offset INTEGER CHECK (arrival_day_offset IS NULL OR arrival_day_offset >= 0),
    departure_day_offset INTEGER CHECK (departure_day_offset IS NULL OR departure_day_offset >= 0),
    call_type TEXT NOT NULL CHECK (call_type IN ('origin', 'passenger_stop', 'destination', 'pass', 'operational_stop', 'unknown')),
    pickup_allowed INTEGER NOT NULL DEFAULT 1 CHECK (pickup_allowed IN (0, 1)),
    dropoff_allowed INTEGER NOT NULL DEFAULT 1 CHECK (dropoff_allowed IN (0, 1)),
    platform TEXT,
    time_accuracy TEXT NOT NULL CHECK (time_accuracy IN ('exact', 'minute', 'approximate', 'unknown')),
    source_id TEXT NOT NULL REFERENCES source_documents(source_id),
    CHECK (arrival_day_offset IS NULL OR arrival_time IS NOT NULL),
    CHECK (departure_day_offset IS NULL OR departure_time IS NOT NULL),
    PRIMARY KEY (trip_id, stop_sequence)
);

CREATE TABLE trip_stop_time_overrides (
    trip_id TEXT NOT NULL,
    service_date TEXT NOT NULL,
    stop_sequence INTEGER NOT NULL,
    arrival_override TEXT,
    departure_override TEXT,
    arrival_seconds_override INTEGER CHECK (arrival_seconds_override IS NULL OR arrival_seconds_override >= 0),
    departure_seconds_override INTEGER CHECK (departure_seconds_override IS NULL OR departure_seconds_override >= 0),
    arrival_day_offset_override INTEGER CHECK (arrival_day_offset_override IS NULL OR arrival_day_offset_override >= 0),
    departure_day_offset_override INTEGER CHECK (departure_day_offset_override IS NULL OR departure_day_offset_override >= 0),
    source_id TEXT NOT NULL REFERENCES source_documents(source_id),
    CHECK (arrival_day_offset_override IS NULL OR arrival_override IS NOT NULL),
    CHECK (departure_day_offset_override IS NULL OR departure_override IS NOT NULL),
    PRIMARY KEY (trip_id, service_date, stop_sequence),
    FOREIGN KEY (trip_id, stop_sequence) REFERENCES stop_times(trip_id, stop_sequence) ON DELETE CASCADE
);

CREATE TABLE trip_number_segments (
    trip_id TEXT NOT NULL REFERENCES trips(trip_id) ON DELETE CASCADE,
    from_sequence INTEGER NOT NULL,
    to_sequence INTEGER NOT NULL,
    train_number TEXT NOT NULL,
    PRIMARY KEY (trip_id, from_sequence),
    CHECK (from_sequence <= to_sequence)
);

CREATE TABLE trip_operator_segments (
    trip_id TEXT NOT NULL REFERENCES trips(trip_id) ON DELETE CASCADE,
    from_sequence INTEGER NOT NULL,
    to_sequence INTEGER NOT NULL,
    operator_id TEXT NOT NULL REFERENCES operators(operator_id),
    PRIMARY KEY (trip_id, from_sequence),
    CHECK (from_sequence <= to_sequence)
);

CREATE TABLE trip_line_segments (
    trip_id TEXT NOT NULL REFERENCES trips(trip_id) ON DELETE CASCADE,
    sequence INTEGER NOT NULL CHECK (sequence >= 0),
    from_station_id TEXT NOT NULL REFERENCES station_identities(station_id),
    to_station_id TEXT NOT NULL REFERENCES station_identities(station_id),
    line_name TEXT NOT NULL,
    operator_id TEXT NOT NULL REFERENCES operators(operator_id),
    reference_kind TEXT CHECK (reference_kind IN ('current_n02', 'historical_overlay')),
    current_n02_line_id TEXT,
    rail_history_id TEXT,
    source_id TEXT NOT NULL REFERENCES source_documents(source_id),
    confidence TEXT NOT NULL CHECK (confidence IN ('high', 'medium', 'low')),
    PRIMARY KEY (trip_id, sequence),
    CHECK (
        (reference_kind IS NULL AND current_n02_line_id IS NULL AND rail_history_id IS NULL)
        OR
        (reference_kind = 'current_n02' AND current_n02_line_id IS NOT NULL AND rail_history_id IS NULL)
        OR
        (reference_kind = 'historical_overlay' AND rail_history_id IS NOT NULL AND current_n02_line_id IS NULL)
    )
);

CREATE TABLE trip_relations (
    trip_id TEXT NOT NULL REFERENCES trips(trip_id) ON DELETE CASCADE,
    related_trip_id TEXT NOT NULL REFERENCES trips(trip_id) ON DELETE CASCADE,
    relation_type TEXT NOT NULL CHECK (relation_type IN ('couples_with', 'splits_from', 'splits_to', 'joins_with', 'through_service_to', 'same_operation_group')),
    from_sequence INTEGER,
    to_sequence INTEGER,
    source_id TEXT NOT NULL REFERENCES source_documents(source_id),
    PRIMARY KEY (trip_id, related_trip_id, relation_type)
);

CREATE TABLE fact_sources (
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    field_name TEXT NOT NULL,
    source_id TEXT NOT NULL REFERENCES source_documents(source_id),
    page_or_locator TEXT,
    confidence TEXT NOT NULL CHECK (confidence IN ('high', 'medium', 'low')),
    verification_status TEXT NOT NULL CHECK (verification_status IN ('verified', 'partial', 'unknown', 'conflict', 'not_applicable')),
    PRIMARY KEY (entity_type, entity_id, field_name, source_id)
);

CREATE TABLE fact_completeness (
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    dimension TEXT NOT NULL CHECK (dimension IN ('identity', 'train_number', 'operator', 'validity_calendar', 'origin_destination', 'stops', 'times', 'route_lines', 'station_refs', 'provenance')),
    status TEXT NOT NULL CHECK (status IN ('verified', 'partial', 'unknown', 'conflict', 'not_applicable')),
    confidence TEXT NOT NULL CHECK (confidence IN ('high', 'medium', 'low')),
    notes TEXT,
    PRIMARY KEY (entity_type, entity_id, dimension)
);

CREATE TABLE verified_zero_service_intervals (
    interval_id TEXT PRIMARY KEY NOT NULL,
    operator_scope TEXT NOT NULL,
    valid_from TEXT NOT NULL,
    valid_until TEXT NOT NULL,
    reason TEXT NOT NULL,
    source_id TEXT NOT NULL REFERENCES source_documents(source_id)
);

CREATE TABLE coverage_declarations (
    coverage_id TEXT PRIMARY KEY NOT NULL,
    operator_scope TEXT NOT NULL,
    year INTEGER NOT NULL CHECK (year BETWEEN 1912 AND 9999),
    dimension TEXT NOT NULL CHECK (dimension IN ('inventory', 'train_number', 'calendar', 'stops', 'times', 'route_lines', 'station_refs', 'provenance')),
    status TEXT NOT NULL CHECK (status IN ('verified', 'partial', 'missing', 'source_gap', 'license_blocked', 'conflict', 'verified_no_service')),
    record_count INTEGER NOT NULL DEFAULT 0 CHECK (record_count >= 0),
    source_id TEXT REFERENCES source_documents(source_id),
    notes TEXT,
    UNIQUE (operator_scope, year, dimension)
);

CREATE TABLE research_queue (
    research_id TEXT PRIMARY KEY NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    missing_dimension TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('open', 'source_unavailable', 'license_blocked', 'not_digitized', 'resolved')),
    notes TEXT
);

CREATE TABLE actual_operation_events (
    event_id TEXT PRIMARY KEY NOT NULL,
    trip_id TEXT NOT NULL REFERENCES trips(trip_id),
    service_date TEXT NOT NULL,
    event_type TEXT NOT NULL,
    source_id TEXT NOT NULL REFERENCES source_documents(source_id),
    notes TEXT
);

CREATE INDEX idx_service_names_lookup ON service_name_periods(name, valid_from, valid_until);
CREATE INDEX idx_services_scope ON services(jr_scope, first_verified_date, last_verified_date);
CREATE INDEX idx_timetable_versions_date ON timetable_versions(effective_from, effective_until);
CREATE INDEX idx_calendars_date ON calendars(valid_from, valid_until);
CREATE INDEX idx_calendar_exceptions_date ON calendar_exceptions(service_date, calendar_id);
CREATE INDEX idx_trips_service ON trips(service_id, timetable_version_id);
CREATE INDEX idx_trips_version ON trips(timetable_version_id, calendar_id);
CREATE INDEX idx_trips_calendar ON trips(calendar_id);
CREATE INDEX idx_stop_times_trip_sequence ON stop_times(trip_id, stop_sequence);
CREATE INDEX idx_stop_times_station ON stop_times(station_id);
CREATE INDEX idx_overrides_date ON trip_stop_time_overrides(service_date, trip_id);
CREATE INDEX idx_operator_segments_trip ON trip_operator_segments(trip_id, from_sequence);
CREATE INDEX idx_line_segments_trip ON trip_line_segments(trip_id, sequence);
CREATE INDEX idx_line_segments_current_identity ON trip_line_segments(current_n02_line_id)
    WHERE current_n02_line_id IS NOT NULL;
CREATE INDEX idx_line_segments_history_identity ON trip_line_segments(rail_history_id)
    WHERE rail_history_id IS NOT NULL;
CREATE INDEX idx_fact_sources_entity ON fact_sources(entity_type, entity_id, field_name);
CREATE INDEX idx_coverage_operator_year ON coverage_declarations(operator_scope, year, status);
