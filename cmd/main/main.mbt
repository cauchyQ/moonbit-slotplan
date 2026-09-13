///|
fn range(start : Int, end : Int) -> @slotplan.Interval {
  match @slotplan.Interval::new(start, end) {
    Ok(value) => value
    Err(_) => panic()
  }
}

///|
fn resource(
  id : String,
  capacity : Int,
  windows : Array[@slotplan.Interval],
) -> @slotplan.ResourceCalendar {
  match
    @slotplan.ResourceCalendar::new(
      id,
      capacity,
      @slotplan.IntervalSet::from_ranges(windows),
    ) {
    Ok(value) => value
    Err(_) => panic()
  }
}

///|
/// A minimal, executable example: schedule a review that needs both a room
/// and a projector, while reserving setup and cleanup time around the event.
fn main {
  let room = resource("atlas-room", 10, [range(540, 720)])
  let projector = resource("projector-7", 1, [range(570, 690)])
  let planner = match @slotplan.Planner::new([room, projector]) {
    Ok(value) => value
    Err(_) => panic()
  }
  let request = match
    @slotplan.BookingRequest::new(
      "design-review",
      45,
      range(600, 680),
      buffer_before=10,
      buffer_after=5,
      required_resources=["atlas-room", "projector-7"],
    ) {
    Ok(value) => value
    Err(_) => panic()
  }
  match planner.reserve_earliest(request) {
    Ok(reservation) => {
      println("scheduled: " + reservation.allocation().render())
      println("reserved: " + reservation.allocation().reserved().render())
    }
    Err(error) => println("cannot schedule: " + error.render())
  }
}
