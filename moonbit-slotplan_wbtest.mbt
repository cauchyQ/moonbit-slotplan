///|
fn must_interval(start : Int, end : Int) -> Interval {
  match Interval::new(start, end) {
    Ok(value) => value
    Err(_) => panic()
  }
}

///|
fn must_resource(
  id : String,
  capacity : Int,
  available : Array[Interval],
) -> ResourceCalendar {
  match
    ResourceCalendar::new(id, capacity, IntervalSet::from_ranges(available)) {
    Ok(value) => value
    Err(_) => panic()
  }
}

///|
fn must_request(
  id : String,
  duration : Int,
  horizon : Interval,
  capacity_needed? : Int = 1,
  buffer_before? : Int = 0,
  buffer_after? : Int = 0,
  required_resources? : Array[String] = [],
) -> BookingRequest {
  match
    BookingRequest::new(
      id,
      duration,
      horizon,
      capacity_needed~,
      buffer_before~,
      buffer_after~,
      required_resources~,
    ) {
    Ok(value) => value
    Err(_) => panic()
  }
}

///|
test "interval set joins adjacency and keeps gaps" {
  let set = IntervalSet::from_ranges([
    must_interval(30, 40),
    must_interval(10, 20),
    must_interval(20, 30),
    must_interval(50, 60),
  ])
  assert_eq(set.ranges(), [must_interval(10, 40), must_interval(50, 60)])
}

///|
test "subtract splits a free interval around a reservation" {
  let free = IntervalSet::from_ranges([must_interval(0, 100)])
  let blocked = IntervalSet::from_ranges([must_interval(35, 65)])
  assert_eq(free.subtract(blocked).ranges(), [
    must_interval(0, 35),
    must_interval(65, 100),
  ])
}

///|
test "resource rejects a range that crosses availability" {
  let room = must_resource("room-a", 8, [must_interval(100, 200)])
  match room.reserve(must_interval(180, 220)) {
    Err(ReservationOutsideAvailability) => ()
    _ => fail("reservation outside availability must fail")
  }
}

///|
test "planner chooses earliest resource with enough capacity" {
  let small = must_resource("small", 2, [must_interval(0, 300)])
  let large = must_resource("large", 12, [must_interval(100, 300)])
  let planner = match Planner::new([small, large]) {
    Ok(value) => value
    Err(_) => fail("planner")
  }
  let request = must_request(
    "team-sync",
    30,
    must_interval(0, 250),
    capacity_needed=6,
  )
  let allocation = match planner.find_earliest(request) {
    Ok(value) => value
    Err(_) => fail("expected allocation")
  }
  assert_eq(allocation.resource_ids(), ["large"])
  assert_eq(allocation.event(), must_interval(100, 130))
}

///|
test "multi-resource booking reserves shared gap including buffers" {
  let room = must_resource("room", 10, [must_interval(0, 200)])
  let projector = must_resource("projector", 1, [must_interval(20, 160)])
  let planner = match Planner::new([room, projector]) {
    Ok(value) => value
    Err(_) => fail("planner")
  }
  let request = must_request(
    "review",
    40,
    must_interval(30, 150),
    buffer_before=10,
    buffer_after=5,
    required_resources=["room", "projector"],
  )
  let reservation = match planner.reserve_earliest(request) {
    Ok(value) => value
    Err(_) => fail("expected reservation")
  }
  assert_eq(reservation.allocation().reserved(), must_interval(20, 75))
  assert_eq(reservation.allocation().event(), must_interval(30, 70))
  let next = reservation.planner()
  let conflict = must_request("follow-up", 20, must_interval(30, 100), required_resources=[
    "room",
  ])
  match next.find_earliest(conflict) {
    Ok(allocation) => assert_eq(allocation.event(), must_interval(75, 95))
    Err(_) => fail("expected post-buffer slot")
  }
}

///|
test "suggestions expose distinct gaps and honor latest strategy" {
  let room = must_resource("room", 12, [
    must_interval(0, 100),
    must_interval(150, 260),
  ])
  let planner = match Planner::new([room]) {
    Ok(value) => value
    Err(_) => fail("planner")
  }
  let request = must_request("interview", 30, must_interval(0, 260))
  let earliest = match planner.suggest(request, limit=4) {
    Ok(value) => value
    Err(_) => fail("suggestions")
  }
  assert_eq(earliest.length(), 2)
  assert_eq(earliest[0].allocation().event(), must_interval(0, 30))
  assert_eq(earliest[1].allocation().event(), must_interval(150, 180))
  let latest = match planner.suggest(request, strategy=Latest, limit=4) {
    Ok(value) => value
    Err(_) => fail("suggestions")
  }
  assert_eq(latest[0].allocation().event(), must_interval(230, 260))
  assert_eq(latest[1].allocation().event(), must_interval(70, 100))
}

///|
test "fragment strategy prefers a window boundary over an interior split" {
  let room = must_resource("room", 12, [
    must_interval(0, 30),
    must_interval(50, 150),
  ])
  let planner = match Planner::new([room]) {
    Ok(value) => value
    Err(_) => fail("planner")
  }
  let request = must_request("repair", 30, must_interval(0, 150))
  let suggestions = match
    planner.suggest(request, strategy=MinimizeFragmentation, limit=4) {
    Ok(value) => value
    Err(_) => fail("suggestions")
  }
  assert_eq(suggestions[0].fragment_count(), 0)
  assert_eq(suggestions[0].allocation().event(), must_interval(0, 30))
}

///|
fn batch_item(
  key : String,
  request : BookingRequest,
  priority? : Int = 0,
) -> BatchItem {
  match BatchItem::new(key, request, priority~) {
    Ok(value) => value
    Err(_) => panic()
  }
}

///|
test "priority batch gives scarce capacity to the highest priority request" {
  let room = must_resource("room", 8, [must_interval(0, 60)])
  let planner = match Planner::new([room]) {
    Ok(value) => value
    Err(_) => fail("planner")
  }
  let low = batch_item(
    "low",
    must_request("low", 45, must_interval(0, 60)),
    priority=1,
  )
  let high = batch_item(
    "high",
    must_request("high", 45, must_interval(0, 60)),
    priority=9,
  )
  let plan = match
    planner.schedule_batch([low, high], policy=PriorityThenEarliest) {
    Ok(value) => value
    Err(_) => fail("batch")
  }
  assert_eq(plan.scheduled_count(), 1)
  assert_eq(plan.outcomes()[0].key(), "high")
  match plan.outcomes()[0].status() {
    Scheduled(_) => ()
    _ => fail("high priority request should win")
  }
  match plan.outcomes()[1].status() {
    Rejected(NoFeasibleSlot("low")) => ()
    _ => fail("low priority request should be rejected")
  }
}

///|
test "atomic batch failure leaves the original planner usable" {
  let room = must_resource("room", 8, [must_interval(0, 60)])
  let planner = match Planner::new([room]) {
    Ok(value) => value
    Err(_) => fail("planner")
  }
  let first = batch_item(
    "first",
    must_request("first", 40, must_interval(0, 60)),
  )
  let second = batch_item(
    "second",
    must_request("second", 40, must_interval(0, 60)),
  )
  match planner.schedule_batch_atomically([first, second]) {
    Err(ItemFailure(key="second", error=NoFeasibleSlot("second"))) => ()
    _ => fail("atomic batch should fail on second item")
  }
  match planner.find_earliest(must_request("after", 60, must_interval(0, 60))) {
    Ok(allocation) => assert_eq(allocation.event(), must_interval(0, 60))
    Err(_) => fail("original planner must remain unchanged")
  }
}

///|
test "cancel releases every resource in a multi-resource allocation" {
  let room = must_resource("room", 8, [must_interval(0, 100)])
  let kit = must_resource("kit", 1, [must_interval(0, 100)])
  let planner = match Planner::new([room, kit]) {
    Ok(value) => value
    Err(_) => fail("planner")
  }
  let request = must_request("lab", 40, must_interval(0, 100), required_resources=[
    "room", "kit",
  ])
  let reservation = match planner.reserve_earliest(request) {
    Ok(value) => value
    Err(_) => fail("reservation")
  }
  let restored = match reservation.planner().cancel(reservation.allocation()) {
    Ok(value) => value
    Err(_) => fail("cancel")
  }
  match
    restored.find_earliest(must_request("again", 100, must_interval(0, 100))) {
    Ok(allocation) => assert_eq(allocation.event(), must_interval(0, 100))
    Err(_) => fail("full availability should be restored")
  }
}

///|
test "reschedule frees old time before looking for replacement" {
  let room = must_resource("room", 8, [must_interval(0, 120)])
  let planner = match Planner::new([room]) {
    Ok(value) => value
    Err(_) => fail("planner")
  }
  let first = must_request("first", 40, must_interval(0, 60))
  let reservation = match planner.reserve_earliest(first) {
    Ok(value) => value
    Err(_) => fail("reservation")
  }
  let moved = match
    reservation
    .planner()
    .reschedule(
      reservation.allocation(),
      must_request("moved", 40, must_interval(70, 120)),
    ) {
    Ok(value) => value
    Err(_) => fail("reschedule")
  }
  assert_eq(moved.previous().event(), must_interval(0, 40))
  assert_eq(moved.replacement().event(), must_interval(70, 110))
  match
    moved
    .planner()
    .find_earliest(must_request("old-slot", 40, must_interval(0, 60))) {
    Ok(allocation) => assert_eq(allocation.event(), must_interval(0, 40))
    Err(_) => fail("old slot should be free after reschedule")
  }
}

///|
test "resource reports account for occupied, free and longest gaps" {
  let room = must_resource("room", 8, [must_interval(0, 120)])
  let planner = match Planner::new([room]) {
    Ok(value) => value
    Err(_) => fail("planner")
  }
  let booked = match
    planner.reserve_earliest(must_request("event", 30, must_interval(30, 60))) {
    Ok(value) => value.planner()
    Err(_) => fail("reservation")
  }
  let report = booked.report(must_interval(0, 120))
  let room_report = report.resources()[0]
  assert_eq(room_report.available_minutes(), 120)
  assert_eq(room_report.occupied_minutes(), 30)
  assert_eq(room_report.free_minutes(), 90)
  assert_eq(room_report.longest_free_minutes(), 60)
  assert_eq(room_report.utilization_percent(), 25)
  assert_eq(room_report.free_percent(), 75)
  assert_eq(room_report.capacity_minutes(), 960)
  assert_eq(room_report.band(), Light)
}

///|
test "planner report surfaces bottlenecks in deterministic resource order" {
  let a = must_resource("a", 4, [must_interval(0, 100)])
  let b = must_resource("b", 4, [must_interval(0, 100)])
  let planner = match Planner::new([a, b]) {
    Ok(value) => value
    Err(_) => fail("planner")
  }
  let booked = match
    planner.reserve_earliest(
      must_request("busy", 80, must_interval(0, 100), required_resources=["b"]),
    ) {
    Ok(value) => value.planner()
    Err(_) => fail("reservation")
  }
  let report = booked.report(must_interval(0, 100))
  assert_eq(report.utilization_percent(), 40)
  assert_eq(report.resource_count(), 2)
  assert_eq(
    report.render_summary(),
    "resources=2 utilization=40% busiest=b@80%",
  )
  assert_eq(report.bottlenecks(70).length(), 1)
  assert_eq(report.bottlenecks(70)[0].resource_id(), "b")
  match report.most_utilized() {
    Some(resource) => assert_eq(resource.resource_id(), "b")
    None => fail("expected a resource report")
  }
}

///|
test "flexible request chooses the earliest compatible equipment group" {
  let room = must_resource("room", 12, [must_interval(0, 120)])
  let camera_a = must_resource("camera-a", 1, [must_interval(60, 120)])
  let camera_b = must_resource("camera-b", 1, [must_interval(20, 120)])
  let planner = match Planner::new([room, camera_a, camera_b]) {
    Ok(value) => value
    Err(_) => fail("planner")
  }
  let request = must_request("recording", 30, must_interval(0, 100), required_resources=[
    "room",
  ])
  let flexible = match
    FlexibleRequest::new(request, [["camera-a"], ["camera-b"]]) {
    Ok(value) => value
    Err(_) => fail("flexible request")
  }
  let allocation = match planner.find_flexible_earliest(flexible) {
    Ok(value) => value
    Err(_) => fail("expected flexible allocation")
  }
  assert_eq(allocation.event(), must_interval(20, 50))
  assert_eq(allocation.resource_ids(), ["room", "camera-b"])
}

///|
test "flexible reservation blocks only the selected alternative" {
  let room = must_resource("room", 12, [must_interval(0, 100)])
  let a = must_resource("a", 1, [must_interval(0, 100)])
  let b = must_resource("b", 1, [must_interval(0, 100)])
  let planner = match Planner::new([room, a, b]) {
    Ok(value) => value
    Err(_) => fail("planner")
  }
  let flexible = match
    FlexibleRequest::new(must_request("first", 50, must_interval(0, 100)), [
      ["a"],
      ["b"],
    ]) {
    Ok(value) => value
    Err(_) => fail("flexible request")
  }
  let next = match planner.reserve_flexible_earliest(flexible) {
    Ok(value) => value.planner()
    Err(_) => fail("reservation")
  }
  let uses_b = match
    FlexibleRequest::new(must_request("second", 100, must_interval(0, 100)), [
      ["b"],
    ]) {
    Ok(value) => value
    Err(_) => fail("flexible request")
  }
  match next.find_flexible_earliest(uses_b) {
    Ok(allocation) => assert_eq(allocation.resource_ids(), ["b"])
    Err(_) => fail("unselected alternative must remain free")
  }
}

///|
fn timeline_event(id : String, start : Int, end : Int) -> TimelineEvent {
  match TimelineEvent::new(id, must_interval(start, end)) {
    Ok(value) => value
    Err(_) => panic()
  }
}

///|
test "timeline layout places overlapping events in separate lanes" {
  let layout = match
    layout_timeline([
      timeline_event("a", 0, 30),
      timeline_event("b", 10, 40),
      timeline_event("c", 40, 60),
    ]) {
    Ok(value) => value
    Err(_) => fail("layout")
  }
  assert_eq(layout.lane_count(), 2)
  assert_eq(layout.peak_concurrency(), 2)
  assert_eq(layout.positions()[0].lane_index(), 0)
  assert_eq(layout.positions()[1].lane_index(), 1)
  assert_eq(layout.positions()[2].lane_index(), 0)
  assert_eq(layout.conflicts().length(), 1)
  assert_eq(layout.conflicts()[0].overlap(), must_interval(10, 30))
}

///|
test "timeline respects adjacency and reports constant concurrency segments" {
  let layout = match
    layout_timeline([timeline_event("a", 0, 20), timeline_event("b", 20, 50)]) {
    Ok(value) => value
    Err(_) => fail("layout")
  }
  assert_eq(layout.lane_count(), 1)
  assert_eq(layout.conflicts().length(), 0)
  assert_eq(layout.concurrency().length(), 2)
  assert_eq(layout.concurrency()[0].interval(), must_interval(0, 20))
  assert_eq(layout.concurrency()[1].interval(), must_interval(20, 50))
}

///|
fn weekly_window(day : Weekday, start : Int, end : Int) -> WeeklyWindow {
  match WeeklyWindow::new(day, start, end) {
    Ok(value) => value
    Err(_) => panic()
  }
}

///|
test "weekly template normalizes day windows and expands repeating weeks" {
  let template = WeeklyTemplate::new([
    weekly_window(Monday, 540, 600),
    weekly_window(Monday, 600, 660),
    weekly_window(Friday, 480, 540),
  ])
  assert_eq(template.windows_for(Monday).ranges(), [must_interval(540, 660)])
  assert_true(template.is_open(Friday, 500))
  assert_true(!template.is_open(Friday, 600))
  let expanded = match template.expand_weeks(0, 2) {
    Ok(value) => value
    Err(_) => fail("expand")
  }
  assert_eq(expanded.ranges(), [
    must_interval(540, 660),
    must_interval(4 * 1440 + 480, 4 * 1440 + 540),
    must_interval(10080 + 540, 10080 + 660),
    must_interval(10080 + 4 * 1440 + 480, 10080 + 4 * 1440 + 540),
  ])
}

///|
test "weekly availability clips to a horizon and creates a bookable resource" {
  let template = WeeklyTemplate::new([
    weekly_window(Monday, 540, 1020),
    weekly_window(Tuesday, 540, 1020),
  ])
  let horizon = must_interval(600, 1440 + 600)
  let availability = match template.availability_within(0, horizon) {
    Ok(value) => value
    Err(_) => fail("availability")
  }
  assert_eq(availability.ranges(), [
    must_interval(600, 1020),
    must_interval(1440 + 540, 1440 + 600),
  ])
  let room = match
    resource_from_weekly_template("room", 6, template, 0, horizon) {
    Ok(value) => value
    Err(_) => fail("resource")
  }
  match room.reserve(must_interval(700, 800)) {
    Ok(_) => ()
    Err(_) => fail("weekly resource should be reservable")
  }
}

///|
test "ledger records create cancel and reschedule transitions" {
  let room = must_resource("room", 8, [must_interval(0, 180)])
  let planner = match Planner::new([room]) {
    Ok(value) => value
    Err(_) => fail("planner")
  }
  let created = match
    BookingLedger::new(planner).book(
      "booking-1",
      must_request("first", 40, must_interval(0, 80)),
    ) {
    Ok(value) => value
    Err(_) => fail("book")
  }
  assert_eq(created.record().state(), Active)
  let moved = match
    created
    .ledger()
    .reschedule(
      "booking-1",
      must_request("second", 40, must_interval(100, 180)),
    ) {
    Ok(value) => value
    Err(_) => fail("reschedule")
  }
  assert_eq(moved.record().allocation().event(), must_interval(100, 140))
  let cancelled = match moved.ledger().cancel("booking-1") {
    Ok(value) => value
    Err(_) => fail("cancel")
  }
  assert_eq(cancelled.record().state(), Cancelled)
  assert_eq(cancelled.ledger().active_records().length(), 0)
  assert_eq(cancelled.ledger().events().length(), 3)
  match cancelled.ledger().events()[2].kind() {
    Cancelled(allocation) =>
      assert_eq(allocation.event(), must_interval(100, 140))
    _ => fail("last event should record cancellation")
  }
}

///|
test "ledger preserves planner state when a reschedule fails" {
  let room = must_resource("room", 8, [must_interval(0, 100)])
  let planner = match Planner::new([room]) {
    Ok(value) => value
    Err(_) => fail("planner")
  }
  let created = match
    BookingLedger::new(planner).book(
      "booking-1",
      must_request("first", 50, must_interval(0, 100)),
    ) {
    Ok(value) => value
    Err(_) => fail("book")
  }
  match
    created
    .ledger()
    .reschedule(
      "booking-1",
      must_request("too-long", 150, must_interval(0, 100)),
    ) {
    Err(SchedulingFailed(NoFeasibleSlot("too-long"))) => ()
    _ => fail("reschedule should fail")
  }
  match
    created
    .ledger()
    .planner()
    .find_earliest(must_request("later", 50, must_interval(0, 100))) {
    Ok(allocation) => assert_eq(allocation.event(), must_interval(50, 100))
    Err(_) => fail("original ledger planner must remain intact")
  }
}

///|
test "availability overlay applies openings and gives closures precedence" {
  let overlay = AvailabilityOverlay::new(
      IntervalSet::from_ranges([must_interval(100, 200)]),
    )
    .open(must_interval(220, 260))
    .close(must_interval(150, 180))
    .close(must_interval(230, 240))
  assert_eq(overlay.resolve().ranges(), [
    must_interval(100, 150),
    must_interval(180, 200),
    must_interval(220, 230),
    must_interval(240, 260),
  ])
  assert_eq(overlay.explain(110), "open by baseline")
  assert_eq(overlay.explain(160), "closed by exception")
  assert_eq(overlay.explain(225), "open by exception")
  assert_eq(overlay.explain(235), "closed by exception")
}

///|
test "availability overlay cannot hide an active reservation" {
  let room = must_resource("room", 8, [must_interval(0, 100)])
  let reserved = match room.reserve(must_interval(30, 60)) {
    Ok(value) => value
    Err(_) => fail("reserve")
  }
  let unsafe_overlay = AvailabilityOverlay::new(
    IntervalSet::from_ranges([must_interval(0, 100)]),
  ).close(must_interval(40, 50))
  match reserved.with_availability_overlay(unsafe_overlay) {
    Err(ExistingReservationOutsideAvailability(range)) =>
      assert_eq(range, must_interval(30, 60))
    _ => fail("active reservation must not be hidden")
  }
  let safe_overlay = AvailabilityOverlay::new(
    IntervalSet::from_ranges([must_interval(0, 100)]),
  ).close(must_interval(70, 80))
  match reserved.with_availability_overlay(safe_overlay) {
    Ok(updated) => assert_true(!updated.is_free(must_interval(70, 80)))
    Err(_) => fail("unrelated closure should be accepted")
  }
}
