///|
/// Failures that are meaningful to a booking UI or command-line adapter.
pub enum PlanError {
  DuplicateResourceId(String)
  UnknownResource(String)
  InsufficientCapacity(Int)
  NoFeasibleSlot(String)
  CannotReserve(String)
  CannotRelease(String)
} derive(Eq, Debug)

///|
pub fn PlanError::render(self : PlanError) -> String {
  match self {
    DuplicateResourceId(id) => "duplicate resource: " + id
    UnknownResource(id) => "unknown resource: " + id
    InsufficientCapacity(capacity) =>
      "insufficient capacity: " + capacity.to_string()
    NoFeasibleSlot(id) => "no feasible slot: " + id
    CannotReserve(id) => "could not reserve resource: " + id
    CannotRelease(id) => "could not release resource: " + id
  }
}

///| A concrete answer to a booking query. `reserved` includes the request's

///|
/// cleanup/setup buffers while `event` is what an end user sees.
pub struct Allocation {
  request_id : String
  event : Interval
  reserved : Interval
  resource_ids : Array[String]
} derive(Debug)

///|
pub fn Allocation::request_id(self : Allocation) -> String {
  self.request_id
}

///|
pub fn Allocation::event(self : Allocation) -> Interval {
  self.event
}

///|
pub fn Allocation::reserved(self : Allocation) -> Interval {
  self.reserved
}

///|
pub fn Allocation::resource_ids(self : Allocation) -> Array[String] {
  self.resource_ids.copy()
}

///|
pub fn Allocation::render(self : Allocation) -> String {
  let mut names = ""
  for index in 0..<self.resource_ids.length() {
    if index > 0 {
      names = names + ","
    }
    names = names + self.resource_ids[index]
  }
  self.request_id + " event=" + self.event.render() + " resources=" + names
}

///| Successful reservation result.  `planner` is the successor state that

///|
/// includes the reservation; the original planner remains unchanged.
pub struct Reservation {
  allocation : Allocation
  planner : Planner
} derive(Debug)

///|
pub fn Reservation::allocation(self : Reservation) -> Allocation {
  self.allocation
}

///|
pub fn Reservation::planner(self : Reservation) -> Planner {
  self.planner
}

///|
/// Output of a successful move.  Retaining both allocations lets a caller

///| explain the change and write an audit record without reverse engineering

///|
/// resource state.
pub struct RescheduleResult {
  previous : Allocation
  replacement : Allocation
  planner : Planner
} derive(Debug)

///|
pub fn RescheduleResult::previous(self : RescheduleResult) -> Allocation {
  self.previous
}

///|
pub fn RescheduleResult::replacement(self : RescheduleResult) -> Allocation {
  self.replacement
}

///|
pub fn RescheduleResult::planner(self : RescheduleResult) -> Planner {
  self.planner
}

///| A small in-memory planning state.  Persistence, authentication and time

///|
/// zone conversion deliberately stay outside this portable core library.
pub struct Planner {
  resources : Array[ResourceCalendar]
} derive(Debug)

///|
pub fn Planner::new(
  resources : Array[ResourceCalendar],
) -> Result[Planner, PlanError] {
  for left in 0..<resources.length() {
    let mut right = left + 1
    while right < resources.length() {
      if resources[left].id() == resources[right].id() {
        return Err(DuplicateResourceId(resources[left].id()))
      }
      right = right + 1
    }
  }
  Ok({ resources: resources.copy() })
}

///|
pub fn Planner::resources(self : Planner) -> Array[ResourceCalendar] {
  self.resources.copy()
}

///|
fn Planner::resource(self : Planner, id : String) -> ResourceCalendar? {
  for resource in self.resources {
    if resource.id() == id {
      return Some(resource)
    }
  }
  None
}

///|
fn Planner::required_calendars(
  self : Planner,
  request : BookingRequest,
) -> Result[Array[ResourceCalendar], PlanError] {
  self.calendars_for_ids(request.required_resources())
}

///|
fn Planner::calendars_for_ids(
  self : Planner,
  ids : Array[String],
) -> Result[Array[ResourceCalendar], PlanError] {
  let selected : Array[ResourceCalendar] = []
  for id in ids {
    match self.resource(id) {
      Some(calendar) => selected.push(calendar)
      None => return Err(UnknownResource(id))
    }
  }
  Ok(selected)
}

///|
fn request_search_window(request : BookingRequest) -> Interval {
  {
    start: request.horizon().start() - request.buffer_before,
    end: request.horizon().end() + request.buffer_after,
  }
}

///|
fn allocation_from_free(
  free : IntervalSet,
  request : BookingRequest,
  ids : Array[String],
) -> Allocation? {
  let search = request_search_window(request)
  match free.first_fit(request.reserved_duration(), search.start()) {
    None => None
    Some(reserved) => {
      let event = request.event_from_reserved(reserved)
      if event.start() < request.horizon().start() ||
        event.end() > request.horizon().end() {
        None
      } else {
        Some({ request_id: request.id(), event, reserved, resource_ids: ids })
      }
    }
  }
}

///|
fn common_free(
  calendars : Array[ResourceCalendar],
  horizon : Interval,
) -> IntervalSet {
  let mut output = calendars[0].free_within(horizon)
  for index in 1..<calendars.length() {
    output = output.intersect(calendars[index].free_within(horizon))
  }
  output
}

///|
/// Find the earliest feasible choice.  With no required resource, each
/// resource that meets `capacity_needed` is considered independently.  With
/// required resources, all listed resources must be free at the same time.
pub fn Planner::find_earliest(
  self : Planner,
  request : BookingRequest,
) -> Result[Allocation, PlanError] {
  let requested = request.required_resources()
  let search = request_search_window(request)
  if requested.length() > 0 {
    let calendars = match self.required_calendars(request) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let free = common_free(calendars, search)
    match allocation_from_free(free, request, requested) {
      Some(allocation) => Ok(allocation)
      None => Err(NoFeasibleSlot(request.id()))
    }
  } else {
    let mut best : Allocation? = None
    let mut found_capacity = false
    for calendar in self.resources {
      if calendar.capacity() < request.capacity_needed() {
        continue
      }
      found_capacity = true
      let ids = [calendar.id()]
      match allocation_from_free(calendar.free_within(search), request, ids) {
        None => ()
        Some(candidate) =>
          match best {
            None => best = Some(candidate)
            Some(current) =>
              if candidate.event().start() < current.event().start() ||
                (
                  candidate.event().start() == current.event().start() &&
                  candidate.resource_ids()[0] < current.resource_ids()[0]
                ) {
                best = Some(candidate)
              }
          }
      }
    }
    match best {
      Some(allocation) => Ok(allocation)
      None =>
        if found_capacity {
          Err(NoFeasibleSlot(request.id()))
        } else {
          Err(InsufficientCapacity(request.capacity_needed()))
        }
    }
  }
}

///|
/// Reserve the earliest matching slot and return a successor planner.  Every
/// target calendar is validated before the successor is returned, preventing
/// partial multi-resource bookings.
pub fn Planner::reserve_earliest(
  self : Planner,
  request : BookingRequest,
) -> Result[Reservation, PlanError] {
  let allocation = match self.find_earliest(request) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let updated : Array[ResourceCalendar] = []
  for calendar in self.resources {
    let mut affected = false
    for id in allocation.resource_ids() {
      if calendar.id() == id {
        affected = true
      }
    }
    if affected {
      match calendar.reserve(allocation.reserved()) {
        Ok(next) => updated.push(next)
        Err(_) => return Err(CannotReserve(calendar.id()))
      }
    } else {
      updated.push(calendar)
    }
  }
  match Planner::new(updated) {
    Ok(planner) => Ok({ allocation, planner })
    Err(error) => Err(error)
  }
}

///|
/// Cancel a known allocation.  All affected calendars are checked before a

///|
/// successor is built, preventing a partial release of a multi-resource slot.
pub fn Planner::cancel(
  self : Planner,
  allocation : Allocation,
) -> Result[Planner, PlanError] {
  for id in allocation.resource_ids() {
    match self.resource(id) {
      None => return Err(UnknownResource(id))
      Some(calendar) =>
        if !calendar.has_reservation(allocation.reserved()) {
          return Err(CannotRelease(id))
        }
    }
  }
  let updated : Array[ResourceCalendar] = []
  for calendar in self.resources {
    let mut affected = false
    for id in allocation.resource_ids() {
      if calendar.id() == id {
        affected = true
      }
    }
    if affected {
      match calendar.release(allocation.reserved()) {
        Ok(next) => updated.push(next)
        Err(_) => return Err(CannotRelease(calendar.id()))
      }
    } else {
      updated.push(calendar)
    }
  }
  Planner::new(updated)
}

///|
/// Move an allocation to the earliest slot matching `replacement`.  A failed

///|
/// replacement attempt does not mutate the caller's original planner.
pub fn Planner::reschedule(
  self : Planner,
  allocation : Allocation,
  replacement : BookingRequest,
) -> Result[RescheduleResult, PlanError] {
  let released = match self.cancel(allocation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match released.reserve_earliest(replacement) {
    Ok(reservation) =>
      Ok({
        previous: allocation,
        replacement: reservation.allocation(),
        planner: reservation.planner(),
      })
    Err(error) => Err(error)
  }
}

///|
pub fn Planner::explain_unavailability(
  self : Planner,
  request : BookingRequest,
) -> String {
  match self.find_earliest(request) {
    Ok(allocation) => "available: " + allocation.render()
    Err(DuplicateResourceId(id)) => "invalid planner: duplicate resource " + id
    Err(UnknownResource(id)) => "unknown required resource: " + id
    Err(InsufficientCapacity(capacity)) =>
      "no resource supplies required capacity " + capacity.to_string()
    Err(NoFeasibleSlot(id)) => "no free slot in horizon for request " + id
    Err(CannotReserve(id)) => "resource changed while reserving: " + id
    Err(CannotRelease(id)) => "allocation is not active on resource: " + id
  }
}
