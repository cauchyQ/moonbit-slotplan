# MoonBit SlotPlan

MoonBit SlotPlan is a small, deterministic scheduling core for **rooms,
equipment, people, or finite-capacity workers**. It is deliberately not a
calendar parser or UI library: an application supplies normalized availability
on an integer timeline and SlotPlan finds a safe booking.

## Why it exists

Date/time libraries, cron parsers, and iCalendar readers answer different
problems. Applications still need a portable algorithm that can answer:

- Which room with capacity for six is free first?
- When are a room and a required projector free at the same time?
- Does setup/cleanup time make an otherwise visible event unsafe?
- Can an application simulate a booking before it changes its own database?

SlotPlan models time as integer `Tick` values, usually UTC minutes. This keeps
time-zone conversion, persistence, authentication, recurrence parsing, and
calendar imports at the application boundary instead of hard-wiring any one
product's rules into the allocator.

## Included capabilities

- Half-open intervals (`[start, end)`) with validation, overlap checks and
  clipping.
- Normalized interval sets with union, intersection, subtraction and first-fit
  lookup.
- Resource calendars with capacity, availability and existing blocked ranges.
- Booking requests with a visible event duration plus setup/cleanup buffers.
- Earliest-slot selection across alternatives, or simultaneous reservation of
  a named group of resources.
- Immutable planning results: `reserve_earliest` returns a successor planner,
  so callers can preview changes safely.
- Human-readable explanations for unavailable requests.
- Batch scheduling with deterministic priority policies and atomic simulation.
- Cancellation, rescheduling and an append-only in-memory booking ledger.
- Alternative all-of resource groups for interchangeable equipment.
- Weekly availability templates, temporary availability exceptions and reports.
- Timeline lane layout, overlap detection and concurrency segments for UIs.

## Run locally

MoonBit toolchain is the only prerequisite.

```text
moon test
moon check --deny-warn
moon run cmd/main
```

The runnable example schedules a 45-minute design review requiring a room and
a projector. It prints both the user-visible event interval and its longer
reserved envelope.

## Browser demonstration

`cmd/web` is a small Rabbita front end compiled to JavaScript. It uses the
same `Planner::suggest` and `Planner::reserve_earliest` calls as library
consumers, so changing a placement strategy or confirming a reservation
recomputes the real scheduling state.

```text
moon build cmd/web --target js --release
```

Open `web/index.html` after the build. The demonstration is intentionally
local-only: it has no account, database, or network service. The user can
adjust the request duration and projector requirement before calculating or
confirming a suggested booking.

## Minimal library example

```moonbit nocheck
///|
let window = Interval::new(540, 720).unwrap()

///|
let room = ResourceCalendar::new(
  "atlas-room",
  10,
  IntervalSet::from_ranges([window]),
).unwrap()

///|
let planner = Planner::new([room]).unwrap()

///|
let request = BookingRequest::new(
  "standup",
  30,
  Interval::new(600, 700).unwrap(),
  capacity_needed=6,
).unwrap()

///|
let allocation = planner.find_earliest(request).unwrap()
```

`allocation.event()` is the meeting itself. `allocation.reserved()` includes
the configured before/after buffers, so a later booking cannot intrude into
turnover time.

## Scope and non-goals

The package is intentionally a pure scheduling algorithm library. Version
0.1 does not parse ICS, RRULE, cron, time zones, holiday datasets, accounts or
databases. Those are integration concerns, and keeping them out means the
same library can serve a classroom booking tool, a laboratory instrument
queue, a CI-worker coordinator, or a small appointment service.

## License

Apache-2.0. See [LICENSE](LICENSE).
