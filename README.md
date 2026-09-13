# MoonBit SlotPlan

MoonBit SlotPlan is a deterministic MoonBit library for finding and reserving
time slots across rooms, equipment, people, or finite-capacity workers. It is
an allocation core, not a calendar UI, ICS reader, Cron parser, or recurrence
engine.

## What it solves

- Normalized half-open intervals and interval-set algebra.
- Availability and occupied time for named resources.
- Capacity-aware earliest-slot selection.
- Simultaneous booking of a required resource group.
- Setup/cleanup buffers that are reserved but hidden from the visible event.
- Multiple slot suggestions using earliest, latest, or low-fragmentation
  placement strategies.
- Immutable reservation results for safe simulation before persistence.
- Batch scheduling with input-order, priority, and shortest-job policies;
  both partial and all-or-nothing execution are supported.
- Cancellation and rescheduling, plus an in-memory booking ledger with an
  append-only transition history.
- Alternative resource groups, such as choosing one compatible projector from
  several candidates.
- Weekly availability templates, temporary openings/closures, and utilization
  reports for capacity planning.
- Timeline lane layout and conflict/concurrency analysis for calendar views.

## Run the local example

```text
moon test
moon check --deny-warn
moon run cmd/main
```

The example books a design review that requires both a meeting room and a
projector. See [README.mbt.md](README.mbt.md) for the API walkthrough and
scope notes.

## Install as a dependency

The published package can be added to another MoonBit module with:

```text
moon add cauchyQ/moonbit-slotplan
```

Then import `cauchyQ/moonbit-slotplan` from that module's `moon.pkg`; the API
walkthrough and minimal example are in [README.mbt.md](README.mbt.md).

## Browser demonstration

The repository also contains a small browser application that uses the real
MoonBit allocator rather than mocked scheduling results:

```text
moon build cmd/web --target js --release
```

Then open `web/index.html` in a browser. The page can switch placement
strategies, adjust duration and projector requirements, display recomputed
suggestions, and simulate confirming the first reservation. It is local-only:
no account, database, network API, or hosted service is involved.

## License

Apache-2.0.
