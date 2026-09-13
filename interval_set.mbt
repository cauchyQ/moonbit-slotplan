///| A normalized, sorted set of half-open intervals.  Its representation is

///|
/// intentionally private so every consumer gets the same adjacency rules.
pub struct IntervalSet {
  ranges : Array[Interval]
} derive(Debug)

///|
pub fn IntervalSet::empty() -> IntervalSet {
  { ranges: [] }
}

///|
pub fn IntervalSet::from_ranges(ranges : Array[Interval]) -> IntervalSet {
  let ordered = ranges.copy()
  ordered.sort()
  let normalized : Array[Interval] = []
  for range in ordered {
    match normalized.last() {
      None => normalized.push(range)
      Some(previous) =>
        match previous.merge(range) {
          Some(joined) => {
            let _ = normalized.pop()
            normalized.push(joined)
          }
          None => normalized.push(range)
        }
    }
  }
  { ranges: normalized }
}

///|
pub fn IntervalSet::ranges(self : IntervalSet) -> Array[Interval] {
  self.ranges.copy()
}

///|
pub fn IntervalSet::is_empty(self : IntervalSet) -> Bool {
  self.ranges.length() == 0
}

///|
pub fn IntervalSet::length(self : IntervalSet) -> Int {
  self.ranges.length()
}

///|
/// Sum the duration of normalized ranges.  Because the representation has no

///|
/// overlaps, this is also the exact covered duration rather than an estimate.
pub fn IntervalSet::total_duration(self : IntervalSet) -> Int {
  let mut total = 0
  for range in self.ranges {
    total = total + range.duration()
  }
  total
}

///|
pub fn IntervalSet::longest_duration(self : IntervalSet) -> Int {
  let mut longest = 0
  for range in self.ranges {
    if range.duration() > longest {
      longest = range.duration()
    }
  }
  longest
}

///|
pub fn IntervalSet::contains(self : IntervalSet, tick : Tick) -> Bool {
  for range in self.ranges {
    if range.contains(tick) {
      return true
    }
    if range.start() > tick {
      return false
    }
  }
  false
}

///|
pub fn IntervalSet::add(self : IntervalSet, range : Interval) -> IntervalSet {
  let ranges = self.ranges.copy()
  ranges.push(range)
  IntervalSet::from_ranges(ranges)
}

///|
pub fn IntervalSet::union(
  self : IntervalSet,
  other : IntervalSet,
) -> IntervalSet {
  let ranges = self.ranges.copy()
  for range in other.ranges {
    ranges.push(range)
  }
  IntervalSet::from_ranges(ranges)
}

///|
pub fn IntervalSet::intersect(
  self : IntervalSet,
  other : IntervalSet,
) -> IntervalSet {
  let output : Array[Interval] = []
  let mut left = 0
  let mut right = 0
  while left < self.ranges.length() && right < other.ranges.length() {
    let a = self.ranges[left]
    let b = other.ranges[right]
    match a.intersect(b) {
      Some(overlap) => output.push(overlap)
      None => ()
    }
    if a.end() < b.end() {
      left = left + 1
    } else {
      right = right + 1
    }
  }
  { ranges: output }
}

///|
/// Return the parts of this set not covered by `blocked`.
pub fn IntervalSet::subtract(
  self : IntervalSet,
  blocked : IntervalSet,
) -> IntervalSet {
  let output : Array[Interval] = []
  for source in self.ranges {
    let mut cursor = source.start()
    for cut in blocked.ranges {
      if cut.end() <= cursor {
        continue
      }
      if cut.start() >= source.end() {
        break
      }
      if cursor < cut.start() {
        let end = if cut.start() < source.end() {
          cut.start()
        } else {
          source.end()
        }
        if cursor < end {
          output.push({ start: cursor, end })
        }
      }
      if cut.end() > cursor {
        cursor = if cut.end() < source.end() { cut.end() } else { source.end() }
      }
      if cursor >= source.end() {
        break
      }
    }
    if cursor < source.end() {
      output.push({ start: cursor, end: source.end() })
    }
  }
  { ranges: output }
}

///|
/// Clip every range to `window`; this is useful before presenting a search
/// result to a caller that requested a finite horizon.
pub fn IntervalSet::within(
  self : IntervalSet,
  window : Interval,
) -> IntervalSet {
  let output : Array[Interval] = []
  for range in self.ranges {
    match range.intersect(window) {
      Some(clipped) => output.push(clipped)
      None => ()
    }
  }
  { ranges: output }
}

///|
pub fn IntervalSet::first_fit(
  self : IntervalSet,
  duration : Int,
  not_before : Tick,
) -> Interval? {
  if duration <= 0 {
    return None
  }
  for free in self.ranges {
    let start = if free.start() > not_before {
      free.start()
    } else {
      not_before
    }
    if free.end() - start >= duration {
      return Some({ start, end: start + duration })
    }
  }
  None
}

///|
pub fn IntervalSet::render(self : IntervalSet) -> String {
  let mut output = ""
  for index in 0..<self.ranges.length() {
    if index > 0 {
      output = output + ", "
    }
    output = output + self.ranges[index].render()
  }
  output
}
