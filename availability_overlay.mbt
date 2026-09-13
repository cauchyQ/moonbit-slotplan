///| Overlay a baseline availability with explicit temporary openings and

///| closures.  It is useful with a weekly template: normal work hours provide

///| the baseline while maintenance, holiday closures, and exceptional overtime

///|
/// are recorded as small interval sets.
pub struct AvailabilityOverlay {
  baseline : IntervalSet
  openings : IntervalSet
  closures : IntervalSet
} derive(Debug)

///|
pub fn AvailabilityOverlay::new(baseline : IntervalSet) -> AvailabilityOverlay {
  { baseline, openings: IntervalSet::empty(), closures: IntervalSet::empty() }
}

///|
pub fn AvailabilityOverlay::baseline(self : AvailabilityOverlay) -> IntervalSet {
  self.baseline
}

///|
pub fn AvailabilityOverlay::openings(self : AvailabilityOverlay) -> IntervalSet {
  self.openings
}

///|
pub fn AvailabilityOverlay::closures(self : AvailabilityOverlay) -> IntervalSet {
  self.closures
}

///|
/// Mark one exceptional opening.  The result is immutable, so a caller may

///|
/// compare tentative availability policies before choosing one.
pub fn AvailabilityOverlay::open(
  self : AvailabilityOverlay,
  range : Interval,
) -> AvailabilityOverlay {
  {
    baseline: self.baseline,
    openings: self.openings.add(range),
    closures: self.closures,
  }
}

///|
/// Mark a closure.  Closures win over both baseline and extra openings,

///|
/// protecting a maintenance window even if an overtime opening overlaps it.
pub fn AvailabilityOverlay::close(
  self : AvailabilityOverlay,
  range : Interval,
) -> AvailabilityOverlay {
  {
    baseline: self.baseline,
    openings: self.openings,
    closures: self.closures.add(range),
  }
}

///|
pub fn AvailabilityOverlay::open_many(
  self : AvailabilityOverlay,
  ranges : Array[Interval],
) -> AvailabilityOverlay {
  let mut output = self
  for range in ranges {
    output = output.open(range)
  }
  output
}

///|
pub fn AvailabilityOverlay::close_many(
  self : AvailabilityOverlay,
  ranges : Array[Interval],
) -> AvailabilityOverlay {
  let mut output = self
  for range in ranges {
    output = output.close(range)
  }
  output
}

///|
/// Materialize the final availability.  The expression is intentionally

///|
/// compact and deterministic: `(baseline ∪ openings) − closures`.
pub fn AvailabilityOverlay::resolve(self : AvailabilityOverlay) -> IntervalSet {
  self.baseline.union(self.openings).subtract(self.closures)
}

///|
pub fn AvailabilityOverlay::resolve_within(
  self : AvailabilityOverlay,
  horizon : Interval,
) -> IntervalSet {
  self.resolve().within(horizon)
}

///|
pub fn AvailabilityOverlay::is_open(
  self : AvailabilityOverlay,
  tick : Tick,
) -> Bool {
  self.resolve().contains(tick)
}

///|
pub fn AvailabilityOverlay::explain(
  self : AvailabilityOverlay,
  tick : Tick,
) -> String {
  if self.closures.contains(tick) {
    "closed by exception"
  } else if self.openings.contains(tick) && !self.baseline.contains(tick) {
    "open by exception"
  } else if self.baseline.contains(tick) {
    "open by baseline"
  } else {
    "outside availability"
  }
}

///| The availability computed for one resource together with the exceptions

///| used to derive it.  Keeping the overlay in the value makes an application

///|
/// able to show users why a resource is unavailable.
pub struct ResolvedAvailability {
  overlay : AvailabilityOverlay
  available : IntervalSet
} derive(Debug)

///|
pub fn ResolvedAvailability::overlay(
  self : ResolvedAvailability,
) -> AvailabilityOverlay {
  self.overlay
}

///|
pub fn ResolvedAvailability::available(
  self : ResolvedAvailability,
) -> IntervalSet {
  self.available
}

///|
pub fn resolve_availability(
  overlay : AvailabilityOverlay,
) -> ResolvedAvailability {
  { overlay, available: overlay.resolve() }
}

///|
pub enum OverlayResourceError {
  EmptyResolvedAvailability
  ExistingReservationOutsideAvailability(Interval)
} derive(Eq, Debug)

///|
/// Apply an overlay to an existing resource without discarding active holds.

///| The operation rejects an exception that would hide a currently reserved

///|
/// range, forcing the host to cancel or reschedule it deliberately first.
pub fn ResourceCalendar::with_availability_overlay(
  self : ResourceCalendar,
  overlay : AvailabilityOverlay,
) -> Result[ResourceCalendar, OverlayResourceError] {
  let available = overlay.resolve()
  if available.is_empty() {
    return Err(EmptyResolvedAvailability)
  }
  for blocked in self.blocked().ranges() {
    let mut covered = false
    for open in available.ranges() {
      if open.contains_interval(blocked) {
        covered = true
      }
    }
    if !covered {
      return Err(ExistingReservationOutsideAvailability(blocked))
    }
  }
  Ok({
    id: self.id(),
    capacity: self.capacity(),
    available,
    blocked: self.blocked(),
  })
}

///|
/// Convenience bridge from a weekly template to an exception-aware resource.
pub fn resource_with_weekly_overlay(
  id : String,
  capacity : Int,
  template : WeeklyTemplate,
  week_start : Tick,
  horizon : Interval,
  openings : Array[Interval],
  closures : Array[Interval],
) -> Result[ResourceCalendar, WeeklyResourceError] {
  let baseline = match template.availability_within(week_start, horizon) {
    Ok(value) => value
    Err(error) => return Err(Weekly(error))
  }
  let overlay = AvailabilityOverlay::new(baseline)
    .open_many(openings)
    .close_many(closures)
  match ResourceCalendar::new(id, capacity, overlay.resolve()) {
    Ok(resource) => Ok(resource)
    Err(error) => Err(Resource(error))
  }
}
