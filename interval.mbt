///| A domain-neutral point on a monotonically increasing timeline.  The

///|
/// caller chooses the unit (usually UTC minutes or integer ticks).
pub type Tick = Int

///|
pub enum IntervalError {
  EmptyOrReversedRange(start~ : Tick, end~ : Tick)
  InvalidWindow(start~ : Tick, end~ : Tick)
} derive(Eq, Debug)

///|
/// A half-open interval `[start, end)`.  Half-open ranges make adjacent
/// reservations compatible: `[10, 20)` and `[20, 30)` do not overlap.
pub struct Interval {
  start : Tick
  end : Tick
} derive(Eq, Compare, Debug)

///|
pub fn Interval::new(
  start : Tick,
  end : Tick,
) -> Result[Interval, IntervalError] {
  if start >= end {
    Err(EmptyOrReversedRange(start~, end~))
  } else {
    Ok({ start, end })
  }
}

///|
pub fn Interval::start(self : Interval) -> Tick {
  self.start
}

///|
pub fn Interval::end(self : Interval) -> Tick {
  self.end
}

///|
pub fn Interval::duration(self : Interval) -> Int {
  self.end - self.start
}

///|
pub fn Interval::contains(self : Interval, tick : Tick) -> Bool {
  self.start <= tick && tick < self.end
}

///|
pub fn Interval::contains_interval(self : Interval, other : Interval) -> Bool {
  self.start <= other.start && other.end <= self.end
}

///|
pub fn Interval::overlaps(self : Interval, other : Interval) -> Bool {
  self.start < other.end && other.start < self.end
}

///|
pub fn Interval::touches(self : Interval, other : Interval) -> Bool {
  self.end == other.start || other.end == self.start
}

///|
pub fn Interval::intersect(self : Interval, other : Interval) -> Interval? {
  let start = if self.start > other.start { self.start } else { other.start }
  let end = if self.end < other.end { self.end } else { other.end }
  if start < end {
    Some({ start, end })
  } else {
    None
  }
}

///|
/// Merge overlapping or immediately adjacent ranges.  Disjoint ranges return
/// `None` so callers cannot accidentally hide an unavailable gap.
pub fn Interval::merge(self : Interval, other : Interval) -> Interval? {
  if !self.overlaps(other) && !self.touches(other) {
    return None
  }
  let start = if self.start < other.start { self.start } else { other.start }
  let end = if self.end > other.end { self.end } else { other.end }
  Some({ start, end })
}

///|
/// Shift an interval on the abstract timeline.  Useful for before/after
/// booking buffers; callers are responsible for choosing a sensible origin.
pub fn Interval::shift(self : Interval, delta : Int) -> Interval {
  { start: self.start + delta, end: self.end + delta }
}

///|
pub fn Interval::with_duration(
  start : Tick,
  duration : Int,
) -> Result[Interval, IntervalError] {
  if duration <= 0 {
    Err(InvalidWindow(start~, end=start + duration))
  } else {
    Interval::new(start, start + duration)
  }
}

///|
pub fn Interval::compare_start(a : Interval, b : Interval) -> Int {
  if a.start < b.start {
    -1
  } else if a.start > b.start {
    1
  } else if a.end < b.end {
    -1
  } else if a.end > b.end {
    1
  } else {
    0
  }
}

///|
pub fn Interval::render(self : Interval) -> String {
  "[" + self.start.to_string() + ", " + self.end.to_string() + ")"
}
