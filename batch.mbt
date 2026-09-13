///| Ordering policy for a set of independent booking requests.  The policies

///|
/// are deterministic so a caller can reproduce and explain a batch result.
pub enum BatchPolicy {
  InputOrder
  PriorityThenEarliest
  ShortestJobFirst
} derive(Eq, Debug)

///|
pub fn batch_policies() -> Array[BatchPolicy] {
  [InputOrder, PriorityThenEarliest, ShortestJobFirst]
}

///|
pub fn BatchPolicy::render(self : BatchPolicy) -> String {
  match self {
    InputOrder => "input-order"
    PriorityThenEarliest => "priority-then-earliest"
    ShortestJobFirst => "shortest-job-first"
  }
}

///| A request plus a caller-defined importance score.  Higher priority wins

///| only when `PriorityThenEarliest` is selected; it never silently changes

///|
/// the default input-order behavior.
pub struct BatchItem {
  key : String
  request : BookingRequest
  priority : Int
} derive(Debug)

///|
pub enum BatchItemError {
  EmptyBatchKey
} derive(Eq, Debug)

///|
pub fn BatchItem::new(
  key : String,
  request : BookingRequest,
  priority? : Int = 0,
) -> Result[BatchItem, BatchItemError] {
  if key.length() == 0 {
    Err(EmptyBatchKey)
  } else {
    Ok({ key, request, priority })
  }
}

///|
pub fn BatchItem::key(self : BatchItem) -> String {
  self.key
}

///|
pub fn BatchItem::request(self : BatchItem) -> BookingRequest {
  self.request
}

///|
pub fn BatchItem::priority(self : BatchItem) -> Int {
  self.priority
}

///|
pub enum BatchError {
  DuplicateBatchKey(String)
  ItemFailure(key~ : String, error~ : PlanError)
} derive(Eq, Debug)

///|
pub fn BatchError::render(self : BatchError) -> String {
  match self {
    DuplicateBatchKey(key) => "duplicate batch key: " + key
    ItemFailure(key~, error~) => key + ": " + error.render()
  }
}

///| Per-item result.  A partial batch retains rejected items as evidence,

///|
/// which is more useful to a booking service than an unexplained omission.
pub enum BatchStatus {
  Scheduled(Allocation)
  Rejected(PlanError)
} derive(Debug)

///|
pub fn BatchStatus::is_scheduled(self : BatchStatus) -> Bool {
  match self {
    Scheduled(_) => true
    Rejected(_) => false
  }
}

///|
pub fn BatchStatus::render(self : BatchStatus) -> String {
  match self {
    Scheduled(allocation) => "scheduled " + allocation.render()
    Rejected(error) => "rejected " + error.render()
  }
}

///|
pub struct BatchOutcome {
  key : String
  request_id : String
  status : BatchStatus
} derive(Debug)

///|
pub fn BatchOutcome::key(self : BatchOutcome) -> String {
  self.key
}

///|
pub fn BatchOutcome::request_id(self : BatchOutcome) -> String {
  self.request_id
}

///|
pub fn BatchOutcome::status(self : BatchOutcome) -> BatchStatus {
  self.status
}

///|
pub struct BatchPlan {
  outcomes : Array[BatchOutcome]
  planner : Planner
  policy : BatchPolicy
} derive(Debug)

///|
pub fn BatchPlan::outcomes(self : BatchPlan) -> Array[BatchOutcome] {
  self.outcomes.copy()
}

///|
pub fn BatchPlan::planner(self : BatchPlan) -> Planner {
  self.planner
}

///|
pub fn BatchPlan::policy(self : BatchPlan) -> BatchPolicy {
  self.policy
}

///|
pub fn BatchPlan::scheduled_count(self : BatchPlan) -> Int {
  let mut count = 0
  for outcome in self.outcomes {
    if outcome.status.is_scheduled() {
      count = count + 1
    }
  }
  count
}

///|
pub fn BatchPlan::rejected_count(self : BatchPlan) -> Int {
  self.outcomes.length() - self.scheduled_count()
}

///|
pub fn BatchPlan::summary(self : BatchPlan) -> String {
  "policy=" +
  self.policy.render() +
  " scheduled=" +
  self.scheduled_count().to_string() +
  " rejected=" +
  self.rejected_count().to_string()
}

///|
fn validate_batch(items : Array[BatchItem]) -> Result[Unit, BatchError] {
  for left in 0..<items.length() {
    let mut right = left + 1
    while right < items.length() {
      if items[left].key() == items[right].key() {
        return Err(DuplicateBatchKey(items[left].key()))
      }
      right = right + 1
    }
  }
  Ok(())
}

///|
fn should_run_before(
  left : BatchItem,
  right : BatchItem,
  policy : BatchPolicy,
) -> Bool {
  match policy {
    InputOrder => false
    PriorityThenEarliest =>
      left.priority() > right.priority() ||
      (
        left.priority() == right.priority() &&
        left.request().horizon().start() < right.request().horizon().start()
      )
    ShortestJobFirst =>
      left.request().duration() < right.request().duration() ||
      (
        left.request().duration() == right.request().duration() &&
        left.request().horizon().start() < right.request().horizon().start()
      )
  }
}

///|
fn order_items(
  items : Array[BatchItem],
  policy : BatchPolicy,
) -> Array[BatchItem] {
  if policy == InputOrder {
    return items.copy()
  }
  let ordered : Array[BatchItem] = []
  for item in items {
    let mut index = 0
    while index < ordered.length() &&
          !should_run_before(item, ordered[index], policy) {
      index = index + 1
    }
    ordered.insert(index, item)
  }
  ordered
}

///|
/// Attempt every item in the selected deterministic order.  A rejection does

///| not roll back earlier successes, so callers can present a useful partial

///|
/// result and optionally retry rejected requests later.
pub fn Planner::schedule_batch(
  self : Planner,
  items : Array[BatchItem],
  policy? : BatchPolicy = InputOrder,
) -> Result[BatchPlan, BatchError] {
  match validate_batch(items) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let mut current = self
  let outcomes : Array[BatchOutcome] = []
  for item in order_items(items, policy) {
    let request = item.request()
    match current.reserve_earliest(request) {
      Ok(reservation) => {
        let allocation = reservation.allocation()
        current = reservation.planner()
        outcomes.push({
          key: item.key(),
          request_id: allocation.request_id(),
          status: Scheduled(allocation),
        })
      }
      Err(error) =>
        outcomes.push({
          key: item.key(),
          request_id: request.id(),
          status: Rejected(error),
        })
    }
  }
  Ok({ outcomes, planner: current, policy })
}

///|
/// Schedule a batch only if every request fits.  On failure, the caller gets

///|
/// the failing item and retains the exact original planner state.
pub fn Planner::schedule_batch_atomically(
  self : Planner,
  items : Array[BatchItem],
  policy? : BatchPolicy = InputOrder,
) -> Result[BatchPlan, BatchError] {
  match validate_batch(items) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let mut current = self
  let outcomes : Array[BatchOutcome] = []
  for item in order_items(items, policy) {
    let request = item.request()
    match current.reserve_earliest(request) {
      Ok(reservation) => {
        let allocation = reservation.allocation()
        current = reservation.planner()
        outcomes.push({
          key: item.key(),
          request_id: allocation.request_id(),
          status: Scheduled(allocation),
        })
      }
      Err(error) => return Err(ItemFailure(key=item.key(), error~))
    }
  }
  Ok({ outcomes, planner: current, policy })
}
