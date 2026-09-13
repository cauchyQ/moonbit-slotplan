///| Week starts on Monday.  The type deliberately models only a repeating

///| seven-day work pattern; dates, time zones and holiday rules remain inputs

///|
/// to the host application.
pub enum Weekday {
  Monday
  Tuesday
  Wednesday
  Thursday
  Friday
  Saturday
  Sunday
} derive(Eq, Debug)

///|
pub fn weekdays() -> Array[Weekday] {
  [Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday]
}

///|
pub fn Weekday::index(self : Weekday) -> Int {
  match self {
    Monday => 0
    Tuesday => 1
    Wednesday => 2
    Thursday => 3
    Friday => 4
    Saturday => 5
    Sunday => 6
  }
}

///|
pub fn Weekday::render(self : Weekday) -> String {
  match self {
    Monday => "monday"
    Tuesday => "tuesday"
    Wednesday => "wednesday"
    Thursday => "thursday"
    Friday => "friday"
    Saturday => "saturday"
    Sunday => "sunday"
  }
}

///|
/// A within-day availability window expressed in minutes after midnight.
pub struct WeeklyWindow {
  day : Weekday
  window : Interval
} derive(Debug)

///|
pub enum WeeklyError {
  WindowOutsideDay(Interval)
  HorizonBeforeWeekStart
  NonPositiveWeekCount(Int)
} derive(Eq, Debug)

///|
pub enum WeeklyResourceError {
  Weekly(WeeklyError)
  Resource(ResourceError)
} derive(Eq, Debug)

///|
pub fn WeeklyWindow::new(
  day : Weekday,
  start_minute : Int,
  end_minute : Int,
) -> Result[WeeklyWindow, WeeklyError] {
  match Interval::new(start_minute, end_minute) {
    Err(_) => Err(WindowOutsideDay({ start: start_minute, end: end_minute }))
    Ok(window) =>
      if start_minute < 0 || end_minute > 1440 {
        Err(WindowOutsideDay(window))
      } else {
        Ok({ day, window })
      }
  }
}

///|
pub fn WeeklyWindow::day(self : WeeklyWindow) -> Weekday {
  self.day
}

///|
pub fn WeeklyWindow::window(self : WeeklyWindow) -> Interval {
  self.window
}

///|
pub fn WeeklyWindow::render(self : WeeklyWindow) -> String {
  self.day.render() + " " + self.window.render()
}

///| A normalized weekly work template.  Overlapping windows on a day are

///|
/// joined so expansion never produces duplicate availability.
pub struct WeeklyTemplate {
  windows : Array[WeeklyWindow]
} derive(Debug)

///|
pub fn WeeklyTemplate::new(windows : Array[WeeklyWindow]) -> WeeklyTemplate {
  let normalized : Array[WeeklyWindow] = []
  for day in weekdays() {
    let day_ranges : Array[Interval] = []
    for window in windows {
      if window.day() == day {
        day_ranges.push(window.window())
      }
    }
    for range in IntervalSet::from_ranges(day_ranges).ranges() {
      normalized.push({ day, window: range })
    }
  }
  { windows: normalized }
}

///|
pub fn WeeklyTemplate::windows(self : WeeklyTemplate) -> Array[WeeklyWindow] {
  self.windows.copy()
}

///|
pub fn WeeklyTemplate::windows_for(
  self : WeeklyTemplate,
  day : Weekday,
) -> IntervalSet {
  let ranges : Array[Interval] = []
  for window in self.windows {
    if window.day() == day {
      ranges.push(window.window())
    }
  }
  IntervalSet::from_ranges(ranges)
}

///|
pub fn WeeklyTemplate::is_open(
  self : WeeklyTemplate,
  day : Weekday,
  minute : Int,
) -> Bool {
  minute >= 0 && minute < 1440 && self.windows_for(day).contains(minute)
}

///|
fn expand_week(template : WeeklyTemplate, week_start : Tick) -> IntervalSet {
  let ranges : Array[Interval] = []
  for window in template.windows {
    let offset = week_start + window.day().index() * 1440
    ranges.push(window.window().shift(offset))
  }
  IntervalSet::from_ranges(ranges)
}

///|
/// Expand exactly `week_count` repeating weeks.  `week_start` is the Monday

///|
/// 00:00 tick chosen by the embedding application.
pub fn WeeklyTemplate::expand_weeks(
  self : WeeklyTemplate,
  week_start : Tick,
  week_count : Int,
) -> Result[IntervalSet, WeeklyError] {
  if week_count <= 0 {
    return Err(NonPositiveWeekCount(week_count))
  }
  let mut output = IntervalSet::empty()
  for week in 0..<week_count {
    output = output.union(expand_week(self, week_start + week * 10080))
  }
  Ok(output)
}

///|
/// Materialize only the repeating windows that overlap `horizon`.  The

///| horizon must use the same tick origin as `week_start` and start no earlier

///|
/// than it, which avoids silently guessing how to handle negative weeks.
pub fn WeeklyTemplate::availability_within(
  self : WeeklyTemplate,
  week_start : Tick,
  horizon : Interval,
) -> Result[IntervalSet, WeeklyError] {
  if horizon.start() < week_start {
    return Err(HorizonBeforeWeekStart)
  }
  let first_week = (horizon.start() - week_start) / 10080
  let last_week = (horizon.end() - 1 - week_start) / 10080
  let mut output = IntervalSet::empty()
  for week in first_week..<(last_week + 1) {
    output = output.union(expand_week(self, week_start + week * 10080))
  }
  Ok(output.within(horizon))
}

///|
/// Construct a bookable resource directly from a weekly template and a finite

///| planning horizon.  Applications may then add holidays or maintenance via

///|
/// `ResourceCalendar::with_blocked`.
pub fn resource_from_weekly_template(
  id : String,
  capacity : Int,
  template : WeeklyTemplate,
  week_start : Tick,
  horizon : Interval,
) -> Result[ResourceCalendar, WeeklyResourceError] {
  let available = match template.availability_within(week_start, horizon) {
    Ok(value) => value
    Err(error) => return Err(Weekly(error))
  }
  match ResourceCalendar::new(id, capacity, available) {
    Ok(value) => Ok(value)
    Err(error) => Err(Resource(error))
  }
}
