///|
/// Errors returned while constructing or changing a resource calendar.
pub enum ResourceError {
  EmptyResourceId
  NonPositiveCapacity(Int)
  EmptyAvailability
  ReservationOutsideAvailability
  ReservationNotFound
} derive(Eq, Debug)

///| A bookable thing: a room, a microscope, a CI worker, or a person whose

///|
/// availability has been supplied by the embedding application.
pub struct ResourceCalendar {
  id : String
  capacity : Int
  available : IntervalSet
  blocked : IntervalSet
} derive(Debug)

///|
pub fn ResourceCalendar::new(
  id : String,
  capacity : Int,
  available : IntervalSet,
) -> Result[ResourceCalendar, ResourceError] {
  if id.length() == 0 {
    Err(EmptyResourceId)
  } else if capacity <= 0 {
    Err(NonPositiveCapacity(capacity))
  } else if available.is_empty() {
    Err(EmptyAvailability)
  } else {
    Ok({ id, capacity, available, blocked: IntervalSet::empty() })
  }
}

///|
pub fn ResourceCalendar::id(self : ResourceCalendar) -> String {
  self.id
}

///|
pub fn ResourceCalendar::capacity(self : ResourceCalendar) -> Int {
  self.capacity
}

///|
pub fn ResourceCalendar::availability(self : ResourceCalendar) -> IntervalSet {
  self.available
}

///|
pub fn ResourceCalendar::blocked(self : ResourceCalendar) -> IntervalSet {
  self.blocked
}

///|
pub fn ResourceCalendar::free_within(
  self : ResourceCalendar,
  horizon : Interval,
) -> IntervalSet {
  self.available.within(horizon).subtract(self.blocked)
}

///|
pub fn ResourceCalendar::is_free(
  self : ResourceCalendar,
  range : Interval,
) -> Bool {
  let free = self.free_within(range)
  for candidate in free.ranges() {
    if candidate.contains_interval(range) {
      return true
    }
  }
  false
}

///|
/// Return a new calendar with the range marked unavailable.  The immutable
/// value style lets callers evaluate alternatives without hidden mutation.
pub fn ResourceCalendar::reserve(
  self : ResourceCalendar,
  range : Interval,
) -> Result[ResourceCalendar, ResourceError] {
  if !self.is_free(range) {
    return Err(ReservationOutsideAvailability)
  }
  Ok({
    id: self.id,
    capacity: self.capacity,
    available: self.available,
    blocked: self.blocked.add(range),
  })
}

///|
/// True only when one normalized blocked range completely covers `range`.
pub fn ResourceCalendar::has_reservation(
  self : ResourceCalendar,
  range : Interval,
) -> Bool {
  for blocked in self.blocked.ranges() {
    if blocked.contains_interval(range) {
      return true
    }
  }
  false
}

///|
/// Return a successor calendar with a prior reservation released.  The range

///| must be covered by an existing reservation so stale clients cannot create

///|
/// availability that was never held.
pub fn ResourceCalendar::release(
  self : ResourceCalendar,
  range : Interval,
) -> Result[ResourceCalendar, ResourceError] {
  if !self.has_reservation(range) {
    return Err(ReservationNotFound)
  }
  Ok({
    id: self.id,
    capacity: self.capacity,
    available: self.available,
    blocked: self.blocked.subtract(IntervalSet::from_ranges([range])),
  })
}

///|
pub fn ResourceCalendar::with_blocked(
  self : ResourceCalendar,
  blocked : IntervalSet,
) -> ResourceCalendar {
  {
    id: self.id,
    capacity: self.capacity,
    available: self.available,
    blocked: self.blocked.union(blocked),
  }
}
