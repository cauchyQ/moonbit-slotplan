///| Human-oriented utilization band.  The thresholds are intentionally

///| conservative: a resource at 85% has little room for disruptions even if

///|
/// it is not technically full.
pub enum UtilizationBand {
  Idle
  Light
  Moderate
  Busy
  Saturated
} derive(Eq, Debug)

///|
pub fn UtilizationBand::render(self : UtilizationBand) -> String {
  match self {
    Idle => "idle"
    Light => "light"
    Moderate => "moderate"
    Busy => "busy"
    Saturated => "saturated"
  }
}

///|
pub fn utilization_band(percent : Int) -> UtilizationBand {
  if percent <= 0 {
    Idle
  } else if percent < 40 {
    Light
  } else if percent < 70 {
    Moderate
  } else if percent < 90 {
    Busy
  } else {
    Saturated
  }
}

///|
/// A resource-level report limited to one caller-supplied horizon.
pub struct ResourceReport {
  resource_id : String
  capacity : Int
  available_minutes : Int
  occupied_minutes : Int
  free_minutes : Int
  longest_free_minutes : Int
  utilization_percent : Int
  band : UtilizationBand
} derive(Debug)

///|
pub fn ResourceReport::resource_id(self : ResourceReport) -> String {
  self.resource_id
}

///|
pub fn ResourceReport::capacity(self : ResourceReport) -> Int {
  self.capacity
}

///|
pub fn ResourceReport::available_minutes(self : ResourceReport) -> Int {
  self.available_minutes
}

///|
pub fn ResourceReport::occupied_minutes(self : ResourceReport) -> Int {
  self.occupied_minutes
}

///|
pub fn ResourceReport::free_minutes(self : ResourceReport) -> Int {
  self.free_minutes
}

///|
pub fn ResourceReport::longest_free_minutes(self : ResourceReport) -> Int {
  self.longest_free_minutes
}

///|
pub fn ResourceReport::utilization_percent(self : ResourceReport) -> Int {
  self.utilization_percent
}

///|
pub fn ResourceReport::free_percent(self : ResourceReport) -> Int {
  if self.available_minutes == 0 {
    0
  } else {
    self.free_minutes * 100 / self.available_minutes
  }
}

///|
/// Total seat/equipment-minute capacity represented by this resource in the

///| report horizon.  A room with capacity ten contributes ten times as much

///|
/// potential person-time as a single-seat resource.
pub fn ResourceReport::capacity_minutes(self : ResourceReport) -> Int {
  self.capacity * self.available_minutes
}

///|
pub fn ResourceReport::band(self : ResourceReport) -> UtilizationBand {
  self.band
}

///|
pub fn ResourceReport::render(self : ResourceReport) -> String {
  self.resource_id +
  " occupied=" +
  self.occupied_minutes.to_string() +
  "/" +
  self.available_minutes.to_string() +
  " utilization=" +
  self.utilization_percent.to_string() +
  "% " +
  self.band.render()
}

///|
pub fn ResourceCalendar::report(
  self : ResourceCalendar,
  horizon : Interval,
) -> ResourceReport {
  let available = self.availability().within(horizon)
  let occupied = self.blocked().within(horizon).intersect(available)
  let free = available.subtract(occupied)
  let available_minutes = available.total_duration()
  let occupied_minutes = occupied.total_duration()
  let utilization_percent = if available_minutes == 0 {
    0
  } else {
    occupied_minutes * 100 / available_minutes
  }
  {
    resource_id: self.id(),
    capacity: self.capacity(),
    available_minutes,
    occupied_minutes,
    free_minutes: free.total_duration(),
    longest_free_minutes: free.longest_duration(),
    utilization_percent,
    band: utilization_band(utilization_percent),
  }
}

///|
/// Aggregated report over every resource in one planner snapshot.
pub struct PlannerReport {
  horizon : Interval
  resources : Array[ResourceReport]
  available_minutes : Int
  occupied_minutes : Int
  free_minutes : Int
} derive(Debug)

///|
pub fn PlannerReport::horizon(self : PlannerReport) -> Interval {
  self.horizon
}

///|
pub fn PlannerReport::resources(self : PlannerReport) -> Array[ResourceReport] {
  self.resources.copy()
}

///|
pub fn PlannerReport::available_minutes(self : PlannerReport) -> Int {
  self.available_minutes
}

///|
pub fn PlannerReport::occupied_minutes(self : PlannerReport) -> Int {
  self.occupied_minutes
}

///|
pub fn PlannerReport::free_minutes(self : PlannerReport) -> Int {
  self.free_minutes
}

///|
pub fn PlannerReport::resource_count(self : PlannerReport) -> Int {
  self.resources.length()
}

///|
pub fn PlannerReport::utilization_percent(self : PlannerReport) -> Int {
  if self.available_minutes == 0 {
    0
  } else {
    self.occupied_minutes * 100 / self.available_minutes
  }
}

///|
pub fn PlannerReport::most_utilized(self : PlannerReport) -> ResourceReport? {
  let mut best : ResourceReport? = None
  for report in self.resources {
    match best {
      None => best = Some(report)
      Some(current) =>
        if report.utilization_percent() > current.utilization_percent() ||
          (
            report.utilization_percent() == current.utilization_percent() &&
            report.resource_id() < current.resource_id()
          ) {
          best = Some(report)
        }
    }
  }
  best
}

///|
/// Return resources at or above an explicit utilization threshold.  Keeping

///| the threshold caller-defined makes this report fit a lab, office or CI

///|
/// fleet without embedding a product-specific policy.
pub fn PlannerReport::bottlenecks(
  self : PlannerReport,
  minimum_percent : Int,
) -> Array[ResourceReport] {
  let output : Array[ResourceReport] = []
  for report in self.resources {
    if report.utilization_percent() >= minimum_percent {
      output.push(report)
    }
  }
  output
}

///|
/// A compact, stable summary suitable for the CLI and a dashboard status

///|
/// card.  Detailed per-resource values remain available through `resources`.
pub fn PlannerReport::render_summary(self : PlannerReport) -> String {
  let busiest = match self.most_utilized() {
    Some(report) =>
      report.resource_id() +
      "@" +
      report.utilization_percent().to_string() +
      "%"
    None => "none"
  }
  "resources=" +
  self.resource_count().to_string() +
  " utilization=" +
  self.utilization_percent().to_string() +
  "% busiest=" +
  busiest
}

///|
pub fn PlannerReport::render_bottlenecks(
  self : PlannerReport,
  minimum_percent : Int,
) -> String {
  let mut output = ""
  for report in self.bottlenecks(minimum_percent) {
    if output.length() > 0 {
      output = output + ", "
    }
    output = output + report.render()
  }
  if output.length() == 0 {
    "none"
  } else {
    output
  }
}

///|
pub fn Planner::report(self : Planner, horizon : Interval) -> PlannerReport {
  let reports : Array[ResourceReport] = []
  let mut available_minutes = 0
  let mut occupied_minutes = 0
  let mut free_minutes = 0
  for resource in self.resources() {
    let report = resource.report(horizon)
    available_minutes = available_minutes + report.available_minutes()
    occupied_minutes = occupied_minutes + report.occupied_minutes()
    free_minutes = free_minutes + report.free_minutes()
    reports.push(report)
  }
  {
    horizon,
    resources: reports,
    available_minutes,
    occupied_minutes,
    free_minutes,
  }
}
