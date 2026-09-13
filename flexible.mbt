///| A request whose mandatory resources may be satisfied by one of several

///| named groups.  Each group is an all-of group; the planner chooses the

///| earliest feasible group, making it suitable for compatible equipment or

///|
/// interchangeable rooms.
pub struct FlexibleRequest {
  request : BookingRequest
  alternatives : Array[Array[String]]
} derive(Debug)

///|
pub enum FlexibleRequestError {
  NoAlternatives
  EmptyAlternative(Int)
  EmptyResourceId(Int, Int)
  DuplicateResourceInAlternative(Int, String)
} derive(Eq, Debug)

///|
pub fn FlexibleRequest::new(
  request : BookingRequest,
  alternatives : Array[Array[String]],
) -> Result[FlexibleRequest, FlexibleRequestError] {
  if alternatives.length() == 0 {
    return Err(NoAlternatives)
  }
  for group_index in 0..<alternatives.length() {
    let group = alternatives[group_index]
    if group.length() == 0 {
      return Err(EmptyAlternative(group_index))
    }
    for resource_index in 0..<group.length() {
      let id = group[resource_index]
      if id.length() == 0 {
        return Err(EmptyResourceId(group_index, resource_index))
      }
      let mut later = resource_index + 1
      while later < group.length() {
        if id == group[later] {
          return Err(DuplicateResourceInAlternative(group_index, id))
        }
        later = later + 1
      }
    }
  }
  Ok({ request, alternatives: alternatives.copy() })
}

///|
pub fn FlexibleRequest::request(self : FlexibleRequest) -> BookingRequest {
  self.request
}

///|
pub fn FlexibleRequest::alternatives(
  self : FlexibleRequest,
) -> Array[Array[String]] {
  self.alternatives.copy()
}

///|
pub fn FlexibleRequest::render(self : FlexibleRequest) -> String {
  self.request.id() + " alternatives=" + self.alternatives.length().to_string()
}

///|
fn append_unique(
  ids : Array[String],
  additions : Array[String],
) -> Array[String] {
  let output = ids.copy()
  for id in additions {
    let mut exists = false
    for current in output {
      if current == id {
        exists = true
      }
    }
    if !exists {
      output.push(id)
    }
  }
  output
}

///|
fn should_choose(candidate : Allocation, current : Allocation) -> Bool {
  candidate.event().start() < current.event().start() ||
  (
    candidate.event().start() == current.event().start() &&
    candidate.resource_ids().join(",") < current.resource_ids().join(",")
  )
}

///|
/// Find the earliest choice among all compatible resource groups.  Resources

///|
/// already mandatory in the underlying request are included in every group.
pub fn Planner::find_flexible_earliest(
  self : Planner,
  flexible : FlexibleRequest,
) -> Result[Allocation, PlanError] {
  let request = flexible.request()
  let mut best : Allocation? = None
  for alternative in flexible.alternatives() {
    let ids = append_unique(request.required_resources(), alternative)
    let calendars = match self.calendars_for_ids(ids) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let search = request_search_window(request)
    match allocation_from_free(common_free(calendars, search), request, ids) {
      None => ()
      Some(candidate) =>
        match best {
          None => best = Some(candidate)
          Some(current) =>
            if should_choose(candidate, current) {
              best = Some(candidate)
            }
        }
    }
  }
  match best {
    Some(value) => Ok(value)
    None => Err(NoFeasibleSlot(request.id()))
  }
}

///|
/// Confirm a flexible selection.  This uses the allocation returned by the

///| same search and validates every selected resource before constructing the

///|
/// successor planner.
pub fn Planner::reserve_flexible_earliest(
  self : Planner,
  flexible : FlexibleRequest,
) -> Result[Reservation, PlanError] {
  let allocation = match self.find_flexible_earliest(flexible) {
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
