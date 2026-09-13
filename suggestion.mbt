///|
/// Strategy for selecting a start within every feasible free interval.
pub enum PlacementStrategy {
  Earliest
  Latest
  MinimizeFragmentation
} derive(Eq, Debug)

///|
pub fn PlacementStrategy::render(self : PlacementStrategy) -> String {
  match self {
    Earliest => "earliest"
    Latest => "latest"
    MinimizeFragmentation => "minimize-fragmentation"
  }
}

///|
/// Enumerate supported strategies for a command-line selector or UI menu.
pub fn placement_strategies() -> Array[PlacementStrategy] {
  [Earliest, Latest, MinimizeFragmentation]
}

///| One feasible slot together with the free window that produced it.  The

///| fragment count is a simple, explainable local measure: zero means the

///| reservation consumes the whole window, one means it leaves one tail, and

///|
/// two means it cuts a window in two.
pub struct Suggestion {
  allocation : Allocation
  free_window : Interval
  fragment_count : Int
} derive(Debug)

///|
pub fn Suggestion::allocation(self : Suggestion) -> Allocation {
  self.allocation
}

///|
pub fn Suggestion::free_window(self : Suggestion) -> Interval {
  self.free_window
}

///|
pub fn Suggestion::fragment_count(self : Suggestion) -> Int {
  self.fragment_count
}

///|
fn max_tick(left : Tick, right : Tick) -> Tick {
  if left > right {
    left
  } else {
    right
  }
}

///|
fn min_tick(left : Tick, right : Tick) -> Tick {
  if left < right {
    left
  } else {
    right
  }
}

///|
/// Produce at most one suggestion from a free window.  A later API can expose

///| an arbitrary grid of starts, but one boundary placement per window keeps

///|
/// v0.1 deterministic and avoids inventing a time granularity.
fn suggestion_from_window(
  window : Interval,
  request : BookingRequest,
  ids : Array[String],
  strategy : PlacementStrategy,
) -> Suggestion? {
  let reserved_duration = request.reserved_duration()
  let first_start = max_tick(
    window.start(),
    request.horizon().start() - request.buffer_before,
  )
  let last_start = min_tick(
    window.end() - reserved_duration,
    request.horizon().end() - request.buffer_before - request.duration(),
  )
  if first_start > last_start {
    return None
  }
  let start = match strategy {
    Latest => last_start
    Earliest | MinimizeFragmentation => first_start
  }
  let reserved = { start, end: start + reserved_duration }
  let event = request.event_from_reserved(reserved)
  let mut fragments = 0
  if window.start() < reserved.start() {
    fragments = fragments + 1
  }
  if reserved.end() < window.end() {
    fragments = fragments + 1
  }
  Some({
    allocation: { request_id: request.id(), event, reserved, resource_ids: ids },
    free_window: window,
    fragment_count: fragments,
  })
}

///|
fn suggestions_from_free(
  free : IntervalSet,
  request : BookingRequest,
  ids : Array[String],
  strategy : PlacementStrategy,
) -> Array[Suggestion] {
  let output : Array[Suggestion] = []
  for window in free.ranges() {
    match suggestion_from_window(window, request, ids.copy(), strategy) {
      Some(suggestion) => output.push(suggestion)
      None => ()
    }
  }
  output
}

///|
fn should_precede(
  left : Suggestion,
  right : Suggestion,
  strategy : PlacementStrategy,
) -> Bool {
  let left_start = left.allocation().event().start()
  let right_start = right.allocation().event().start()
  match strategy {
    Earliest =>
      left_start < right_start ||
      (
        left_start == right_start &&
        left.allocation().resource_ids()[0] <
        right.allocation().resource_ids()[0]
      )
    Latest =>
      left_start > right_start ||
      (
        left_start == right_start &&
        left.allocation().resource_ids()[0] <
        right.allocation().resource_ids()[0]
      )
    MinimizeFragmentation =>
      left.fragment_count() < right.fragment_count() ||
      (
        left.fragment_count() == right.fragment_count() &&
        left_start < right_start
      ) ||
      (
        left.fragment_count() == right.fragment_count() &&
        left_start == right_start &&
        left.allocation().resource_ids()[0] <
        right.allocation().resource_ids()[0]
      )
  }
}

///|
/// Stable insertion sort is sufficient here because the number of free gaps

///| in a scheduling query is usually small, and it keeps the core dependency

///|
/// free.  Upgrade to indexed sorting only after a real profile shows need.
fn sort_suggestions(
  values : Array[Suggestion],
  strategy : PlacementStrategy,
) -> Array[Suggestion] {
  let output : Array[Suggestion] = []
  for value in values {
    let mut index = 0
    while index < output.length() &&
          !should_precede(value, output[index], strategy) {
      index = index + 1
    }
    output.insert(index, value)
  }
  output
}

///|
/// Return distinct boundary placements from each currently free interval.

///| This is useful for a UI that should show alternatives instead of silently

///|
/// picking a single booking.  `limit <= 0` means no suggestions.
pub fn Planner::suggest(
  self : Planner,
  request : BookingRequest,
  strategy? : PlacementStrategy = Earliest,
  limit? : Int = 5,
) -> Result[Array[Suggestion], PlanError] {
  if limit <= 0 {
    return Ok([])
  }
  let search = request_search_window(request)
  let values : Array[Suggestion] = []
  let required = request.required_resources()
  if required.length() > 0 {
    let calendars = match self.required_calendars(request) {
      Ok(found) => found
      Err(error) => return Err(error)
    }
    for
      value in suggestions_from_free(
        common_free(calendars, search),
        request,
        required,
        strategy,
      ) {
      values.push(value)
    }
  } else {
    let mut found_capacity = false
    for calendar in self.resources {
      if calendar.capacity() < request.capacity_needed() {
        continue
      }
      found_capacity = true
      for
        value in suggestions_from_free(
          calendar.free_within(search),
          request,
          [calendar.id()],
          strategy,
        ) {
        values.push(value)
      }
    }
    if !found_capacity {
      return Err(InsufficientCapacity(request.capacity_needed()))
    }
  }
  let ordered = sort_suggestions(values, strategy)
  let result : Array[Suggestion] = []
  for index in 0..<ordered.length() {
    if index >= limit {
      break
    }
    result.push(ordered[index])
  }
  Ok(result)
}
