///|
/// A request to reserve one or more resources at the same time.
pub struct BookingRequest {
  id : String
  duration : Int
  horizon : Interval
  capacity_needed : Int
  buffer_before : Int
  buffer_after : Int
  required_resources : Array[String]
} derive(Debug)

///|
pub enum RequestError {
  EmptyRequestId
  NonPositiveDuration(Int)
  NonPositiveCapacity(Int)
  NegativeBuffer(Int)
  EmptyRequiredResource
} derive(Eq, Debug)

///|
pub fn BookingRequest::new(
  id : String,
  duration : Int,
  horizon : Interval,
  capacity_needed? : Int = 1,
  buffer_before? : Int = 0,
  buffer_after? : Int = 0,
  required_resources? : Array[String] = [],
) -> Result[BookingRequest, RequestError] {
  if id.length() == 0 {
    Err(EmptyRequestId)
  } else if duration <= 0 {
    Err(NonPositiveDuration(duration))
  } else if capacity_needed <= 0 {
    Err(NonPositiveCapacity(capacity_needed))
  } else if buffer_before < 0 {
    Err(NegativeBuffer(buffer_before))
  } else if buffer_after < 0 {
    Err(NegativeBuffer(buffer_after))
  } else {
    for resource in required_resources {
      if resource.length() == 0 {
        return Err(EmptyRequiredResource)
      }
    }
    Ok({
      id,
      duration,
      horizon,
      capacity_needed,
      buffer_before,
      buffer_after,
      required_resources,
    })
  }
}

///|
pub fn BookingRequest::id(self : BookingRequest) -> String {
  self.id
}

///|
pub fn BookingRequest::duration(self : BookingRequest) -> Int {
  self.duration
}

///|
pub fn BookingRequest::horizon(self : BookingRequest) -> Interval {
  self.horizon
}

///|
pub fn BookingRequest::capacity_needed(self : BookingRequest) -> Int {
  self.capacity_needed
}

///|
pub fn BookingRequest::required_resources(
  self : BookingRequest,
) -> Array[String] {
  self.required_resources.copy()
}

///|
pub fn BookingRequest::reserved_duration(self : BookingRequest) -> Int {
  self.duration + self.buffer_before + self.buffer_after
}

///|
/// Convert a reserved envelope back to the customer-visible appointment.
pub fn BookingRequest::event_from_reserved(
  self : BookingRequest,
  reserved : Interval,
) -> Interval {
  {
    start: reserved.start() + self.buffer_before,
    end: reserved.end() - self.buffer_after,
  }
}

///|
pub fn BookingRequest::render(self : BookingRequest) -> String {
  self.id +
  " duration=" +
  self.duration.to_string() +
  " horizon=" +
  self.horizon.render()
}
