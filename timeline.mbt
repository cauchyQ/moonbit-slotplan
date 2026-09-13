///| A named event for rendering or collision analysis.  The event is kept

///| independent of `Allocation` so a consumer may visualize imported data as

///|
/// well as reservations produced by SlotPlan.
pub struct TimelineEvent {
  id : String
  interval : Interval
  label : String
} derive(Debug)

///|
pub enum TimelineError {
  EmptyEventId
  DuplicateEventId(String)
} derive(Eq, Debug)

///|
pub fn TimelineEvent::new(
  id : String,
  interval : Interval,
  label? : String = "",
) -> Result[TimelineEvent, TimelineError] {
  if id.length() == 0 {
    Err(EmptyEventId)
  } else {
    Ok({ id, interval, label })
  }
}

///|
pub fn TimelineEvent::id(self : TimelineEvent) -> String {
  self.id
}

///|
pub fn TimelineEvent::interval(self : TimelineEvent) -> Interval {
  self.interval
}

///|
pub fn TimelineEvent::label(self : TimelineEvent) -> String {
  self.label
}

///|
pub fn TimelineEvent::from_allocation(allocation : Allocation) -> TimelineEvent {
  {
    id: allocation.request_id(),
    interval: allocation.event(),
    label: allocation.resource_ids().join(", "),
  }
}

///| Position information for a visual event.  `lane_count` is the total

///| number of simultaneous lanes in the layout, so a renderer can use

///|
/// `lane_index / lane_count` as a stable horizontal fraction.
pub struct TimelinePosition {
  event : TimelineEvent
  lane_index : Int
  lane_count : Int
} derive(Debug)

///|
pub fn TimelinePosition::event(self : TimelinePosition) -> TimelineEvent {
  self.event
}

///|
pub fn TimelinePosition::lane_index(self : TimelinePosition) -> Int {
  self.lane_index
}

///|
pub fn TimelinePosition::lane_count(self : TimelinePosition) -> Int {
  self.lane_count
}

///|
pub fn TimelinePosition::left_percent(self : TimelinePosition) -> Int {
  if self.lane_count == 0 {
    0
  } else {
    self.lane_index * 100 / self.lane_count
  }
}

///|
pub fn TimelinePosition::width_percent(self : TimelinePosition) -> Int {
  if self.lane_count == 0 {
    100
  } else {
    100 / self.lane_count
  }
}

///| A pair of truly overlapping events.  Adjacent half-open events are not a

///|
/// conflict, which matches booking semantics elsewhere in the library.
pub struct ConflictPair {
  first : TimelineEvent
  second : TimelineEvent
  overlap : Interval
} derive(Debug)

///|
pub fn ConflictPair::first(self : ConflictPair) -> TimelineEvent {
  self.first
}

///|
pub fn ConflictPair::second(self : ConflictPair) -> TimelineEvent {
  self.second
}

///|
pub fn ConflictPair::overlap(self : ConflictPair) -> Interval {
  self.overlap
}

///|
/// One interval with a constant number of active events.
pub struct ConcurrencySegment {
  interval : Interval
  count : Int
} derive(Debug)

///|
pub fn ConcurrencySegment::interval(self : ConcurrencySegment) -> Interval {
  self.interval
}

///|
pub fn ConcurrencySegment::count(self : ConcurrencySegment) -> Int {
  self.count
}

///|
/// Full result of a greedy interval-partitioning layout.
pub struct TimelineLayout {
  positions : Array[TimelinePosition]
  lane_count : Int
  conflicts : Array[ConflictPair]
  concurrency : Array[ConcurrencySegment]
} derive(Debug)

///|
pub fn TimelineLayout::positions(
  self : TimelineLayout,
) -> Array[TimelinePosition] {
  self.positions.copy()
}

///|
pub fn TimelineLayout::lane_count(self : TimelineLayout) -> Int {
  self.lane_count
}

///|
pub fn TimelineLayout::conflicts(self : TimelineLayout) -> Array[ConflictPair] {
  self.conflicts.copy()
}

///|
pub fn TimelineLayout::concurrency(
  self : TimelineLayout,
) -> Array[ConcurrencySegment] {
  self.concurrency.copy()
}

///|
pub fn TimelineLayout::peak_concurrency(self : TimelineLayout) -> Int {
  let mut peak = 0
  for segment in self.concurrency {
    if segment.count() > peak {
      peak = segment.count()
    }
  }
  peak
}

///|
fn compare_events(left : TimelineEvent, right : TimelineEvent) -> Int {
  let by_interval = Interval::compare_start(left.interval(), right.interval())
  if by_interval != 0 {
    by_interval
  } else if left.id() < right.id() {
    -1
  } else if left.id() > right.id() {
    1
  } else {
    0
  }
}

///|
fn sort_events(events : Array[TimelineEvent]) -> Array[TimelineEvent] {
  let output : Array[TimelineEvent] = []
  for event in events {
    let mut index = 0
    while index < output.length() && compare_events(output[index], event) <= 0 {
      index = index + 1
    }
    output.insert(index, event)
  }
  output
}

///|
fn point_precedes(left : (Tick, Int), right : (Tick, Int)) -> Bool {
  left.0 < right.0 || (left.0 == right.0 && left.1 < right.1)
}

///|
fn sort_points(points : Array[(Tick, Int)]) -> Array[(Tick, Int)] {
  let output : Array[(Tick, Int)] = []
  for point in points {
    let mut index = 0
    while index < output.length() && !point_precedes(point, output[index]) {
      index = index + 1
    }
    output.insert(index, point)
  }
  output
}

///|
fn validate_events(
  events : Array[TimelineEvent],
) -> Result[Unit, TimelineError] {
  for left in 0..<events.length() {
    let mut right = left + 1
    while right < events.length() {
      if events[left].id() == events[right].id() {
        return Err(DuplicateEventId(events[left].id()))
      }
      right = right + 1
    }
  }
  Ok(())
}

///|
fn all_conflicts(events : Array[TimelineEvent]) -> Array[ConflictPair] {
  let output : Array[ConflictPair] = []
  for left in 0..<events.length() {
    let mut right = left + 1
    while right < events.length() {
      match events[left].interval().intersect(events[right].interval()) {
        Some(overlap) =>
          output.push({ first: events[left], second: events[right], overlap })
        None => ()
      }
      right = right + 1
    }
  }
  output
}

///|
/// Derive contiguous segments of equal event concurrency with a small sweep

///| over sorted boundaries.  End boundaries are processed before starts at the

///|
/// same tick, preserving half-open interval semantics.
fn concurrency_segments(
  events : Array[TimelineEvent],
) -> Array[ConcurrencySegment] {
  let points : Array[(Tick, Int)] = []
  for event in events {
    points.push((event.interval().start(), 1))
    points.push((event.interval().end(), -1))
  }
  let ordered = sort_points(points)
  let output : Array[ConcurrencySegment] = []
  let mut count = 0
  let mut index = 0
  while index < ordered.length() {
    let tick = ordered[index].0
    while index < ordered.length() && ordered[index].0 == tick {
      count = count + ordered[index].1
      index = index + 1
    }
    if index < ordered.length() && tick < ordered[index].0 && count > 0 {
      output.push({ interval: { start: tick, end: ordered[index].0 }, count })
    }
  }
  output
}

///|
/// Assign each event to the first lane that has ended.  This greedy interval

///| partitioning is optimal for interval graphs: the number of lanes equals

///|
/// the peak concurrent-event count.
pub fn layout_timeline(
  events : Array[TimelineEvent],
) -> Result[TimelineLayout, TimelineError] {
  match validate_events(events) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let ordered = sort_events(events)
  let lane_ends : Array[Tick] = []
  let prelim : Array[(TimelineEvent, Int)] = []
  for event in ordered {
    let mut lane = 0
    while lane < lane_ends.length() &&
          lane_ends[lane] > event.interval().start() {
      lane = lane + 1
    }
    if lane == lane_ends.length() {
      lane_ends.push(event.interval().end())
    } else {
      lane_ends[lane] = event.interval().end()
    }
    prelim.push((event, lane))
  }
  let positions : Array[TimelinePosition] = []
  for entry in prelim {
    positions.push({
      event: entry.0,
      lane_index: entry.1,
      lane_count: lane_ends.length(),
    })
  }
  Ok({
    positions,
    lane_count: lane_ends.length(),
    conflicts: all_conflicts(ordered),
    concurrency: concurrency_segments(ordered),
  })
}
