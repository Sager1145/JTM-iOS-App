# RailBench — numbers for the pure tiers

    cd ios/tools/bench
    swift build -c release --scratch-path /tmp/jtm-bench
    /tmp/jtm-bench/release/RailBench            # everything
    /tmp/jtm-bench/release/RailBench tap search # named suites only

Suites: `search`, `stations`, `predicates`, `tap`, `rebuild`, `statistics`,
`routes`, `editor`.

## Why this is a separate package

`swift test` is the gate. It has to be fast and it has to answer pass or fail,
and a benchmark is neither — what is wanted from one is a *number*, repeated
enough times to have a median. Mixing them would make the gate slow and the
benchmark's answers hostage to whatever else the test runner is doing.

It depends on `../../RailKit` by path, so it measures the sources the app
ships rather than a copy, and it reads the real fixtures out of the repository
(`app/data/sample-data`, `app/public/rail`, `app/data/rail-sections*.json`).
Invented inputs are tidy in exactly the ways production data is not.

## What it can and cannot tell you

It runs on the **host**, in **release**, over the **real data**. So it is
evidence about arithmetic: how long a locale-aware substring search takes over
4,112 real strings, how many vertices a tap has to project, what one journey's
edge matching costs. It is repeatable, which a hand-timed interaction is not.

It cannot see MapKit, SwiftUI, storage or the phone's memory system. A number
here is a **lower bound** on the device and a statement about *proportion*
rather than about absolute time. Anything about a frame, a hitch or a gesture
needs a device trace — see `RailMap/RailSignpost.swift` for the instrumentation
that is already in the app for exactly that, and the recording recipe in its
documentation.

## Reading the output

Each line is `median / p95 / min` over nine runs after two untimed warm-ups.
Median rather than mean because a host with other work on it has a long right
tail; p95 rather than max because the maximum of nine runs samples the
scheduler more than the code.

Results are consumed through `blackHole` so the optimiser cannot delete the
work being measured, which is the classic way a micro-benchmark reports zero.

## Adding one

Write `benchmarkX(root:)` in its own file, call `measure(...)` inside it, and
add a line to `main.swift`. If the benchmark exists to justify a change, make
it print the **before and the after side by side** — `TapBench` runs the old
full-projection path and the new culled one over the same geometry, and asserts
they return the same answer before reporting how much faster one of them is. A
speed-up whose correctness is not checked in the same breath is not evidence.
