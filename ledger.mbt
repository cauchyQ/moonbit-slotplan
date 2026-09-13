///| Lifecycle state for a booking record.  Records are retained after

///|
/// cancellation so an embedding application can preserve an audit trail.
pub enum BookingState {
  Active
  Cancelled
} derive(Eq, Debug)

///|
pub fn BookingState::render(self : BookingState) -> String {
  match self {
    Active => "active"
    Cancelled => "cancelled"
  }
}

///|
/// A named allocation held in the ledger.
pub struct BookingRecord {
  booking_id : String
  allocation : Allocation
  state : BookingState
} derive(Debug)

///|
pub fn BookingRecord::booking_id(self : BookingRecord) -> String {
  self.booking_id
}

///|
pub fn BookingRecord::allocation(self : BookingRecord) -> Allocation {
  self.allocation
}

///|
pub fn BookingRecord::state(self : BookingRecord) -> BookingState {
  self.state
}

///|
pub fn BookingRecord::is_active(self : BookingRecord) -> Bool {
  self.state == Active
}

///|
pub fn BookingRecord::render(self : BookingRecord) -> String {
  self.booking_id + " " + self.state.render() + " " + self.allocation.render()
}

///| Append-only transition record.  It is intentionally simple enough for a

///|
/// UI, CLI or persistence adapter to map into its own storage format.
pub enum LedgerEventKind {
  Created(Allocation)
  Cancelled(Allocation)
  Rescheduled(previous~ : Allocation, replacement~ : Allocation)
} derive(Debug)

///|
pub struct LedgerEvent {
  sequence : Int
  booking_id : String
  kind : LedgerEventKind
} derive(Debug)

///|
pub fn LedgerEvent::sequence(self : LedgerEvent) -> Int {
  self.sequence
}

///|
pub fn LedgerEvent::booking_id(self : LedgerEvent) -> String {
  self.booking_id
}

///|
pub fn LedgerEvent::kind(self : LedgerEvent) -> LedgerEventKind {
  self.kind
}

///|
pub enum LedgerError {
  EmptyBookingId
  DuplicateBookingId(String)
  UnknownBookingId(String)
  BookingNotActive(String)
  SchedulingFailed(PlanError)
} derive(Eq, Debug)

///|
pub fn LedgerError::render(self : LedgerError) -> String {
  match self {
    EmptyBookingId => "booking id cannot be empty"
    DuplicateBookingId(id) => "booking id already exists: " + id
    UnknownBookingId(id) => "unknown booking id: " + id
    BookingNotActive(id) => "booking is not active: " + id
    SchedulingFailed(error) => error.render()
  }
}

///| An immutable in-memory coordination layer over `Planner`.  This is not a

///| database; it provides a correct state model that a database adapter can

///|
/// persist without duplicating cancellation and rescheduling behavior.
pub struct BookingLedger {
  planner : Planner
  records : Array[BookingRecord]
  events : Array[LedgerEvent]
} derive(Debug)

///|
pub struct LedgerChange {
  ledger : BookingLedger
  record : BookingRecord
} derive(Debug)

///|
pub fn LedgerChange::ledger(self : LedgerChange) -> BookingLedger {
  self.ledger
}

///|
pub fn LedgerChange::record(self : LedgerChange) -> BookingRecord {
  self.record
}

///|
pub fn BookingLedger::new(planner : Planner) -> BookingLedger {
  { planner, records: [], events: [] }
}

///|
pub fn BookingLedger::planner(self : BookingLedger) -> Planner {
  self.planner
}

///|
pub fn BookingLedger::records(self : BookingLedger) -> Array[BookingRecord] {
  self.records.copy()
}

///|
pub fn BookingLedger::events(self : BookingLedger) -> Array[LedgerEvent] {
  self.events.copy()
}

///|
pub fn BookingLedger::active_records(
  self : BookingLedger,
) -> Array[BookingRecord] {
  let output : Array[BookingRecord] = []
  for record in self.records {
    if record.is_active() {
      output.push(record)
    }
  }
  output
}

///|
fn BookingLedger::index_of(self : BookingLedger, booking_id : String) -> Int? {
  for index in 0..<self.records.length() {
    if self.records[index].booking_id() == booking_id {
      return Some(index)
    }
  }
  None
}

///|
fn next_event(
  events : Array[LedgerEvent],
  booking_id : String,
  kind : LedgerEventKind,
) -> LedgerEvent {
  { sequence: events.length() + 1, booking_id, kind }
}

///|
fn with_event(
  planner : Planner,
  records : Array[BookingRecord],
  events : Array[LedgerEvent],
  booking_id : String,
  kind : LedgerEventKind,
) -> BookingLedger {
  let updated_events = events.copy()
  updated_events.push(next_event(updated_events, booking_id, kind))
  { planner, records, events: updated_events }
}

///|
/// Create and retain the earliest allocation for one application-level ID.
pub fn BookingLedger::book(
  self : BookingLedger,
  booking_id : String,
  request : BookingRequest,
) -> Result[LedgerChange, LedgerError] {
  if booking_id.length() == 0 {
    return Err(EmptyBookingId)
  }
  if self.index_of(booking_id) is Some(_) {
    return Err(DuplicateBookingId(booking_id))
  }
  let reservation = match self.planner.reserve_earliest(request) {
    Ok(value) => value
    Err(error) => return Err(SchedulingFailed(error))
  }
  let record = {
    booking_id,
    allocation: reservation.allocation(),
    state: Active,
  }
  let records = self.records.copy()
  records.push(record)
  let ledger = with_event(
    reservation.planner(),
    records,
    self.events,
    booking_id,
    Created(record.allocation()),
  )
  Ok({ ledger, record })
}

///|
/// Cancel an active record and retain its original allocation in history.
pub fn BookingLedger::cancel(
  self : BookingLedger,
  booking_id : String,
) -> Result[LedgerChange, LedgerError] {
  let index = match self.index_of(booking_id) {
    Some(value) => value
    None => return Err(UnknownBookingId(booking_id))
  }
  let current = self.records[index]
  if !current.is_active() {
    return Err(BookingNotActive(booking_id))
  }
  let planner = match self.planner.cancel(current.allocation()) {
    Ok(value) => value
    Err(error) => return Err(SchedulingFailed(error))
  }
  let record = {
    booking_id: current.booking_id(),
    allocation: current.allocation(),
    state: Cancelled,
  }
  let records = self.records.copy()
  records[index] = record
  let ledger = with_event(
    planner,
    records,
    self.events,
    booking_id,
    Cancelled(current.allocation()),
  )
  Ok({ ledger, record })
}

///|
/// Replace an active record's allocation while preserving its booking ID and

///| recording the before/after pair.  The operation is all-or-nothing because

///|
/// `Planner::reschedule` is immutable.
pub fn BookingLedger::reschedule(
  self : BookingLedger,
  booking_id : String,
  request : BookingRequest,
) -> Result[LedgerChange, LedgerError] {
  let index = match self.index_of(booking_id) {
    Some(value) => value
    None => return Err(UnknownBookingId(booking_id))
  }
  let current = self.records[index]
  if !current.is_active() {
    return Err(BookingNotActive(booking_id))
  }
  let result = match self.planner.reschedule(current.allocation(), request) {
    Ok(value) => value
    Err(error) => return Err(SchedulingFailed(error))
  }
  let record = {
    booking_id: current.booking_id(),
    allocation: result.replacement(),
    state: Active,
  }
  let records = self.records.copy()
  records[index] = record
  let ledger = with_event(
    result.planner(),
    records,
    self.events,
    booking_id,
    Rescheduled(previous=current.allocation(), replacement=result.replacement()),
  )
  Ok({ ledger, record })
}
