# OCCTSwiftMetalDemo

Interactive Metal demo for OCCTSwiftViewport — galleries of curves, surfaces,
sweeps, projections, annotations, selection, and the `DemoTestRunner` stress
harness.

It is a **separate package** from the root `OCCTSwiftViewport` library because
it depends on the kernel (`OCCTSwift`) and the bridge layer (`OCCTSwiftTools`),
and `OCCTSwiftTools` depends back on `OCCTSwiftViewport`. Keeping the demo here
prevents that cycle from leaking into the published Viewport manifest, which
stays dependency-free. See the comment in `Package.swift`.

## Run

```bash
# from the repo root
swift run --package-path Examples/MetalDemo OCCTSwiftMetalDemo

# headless stress suite (used by scripts/overnight-stress.sh)
swift build --package-path Examples/MetalDemo
Examples/MetalDemo/.build/debug/OCCTSwiftMetalDemo --test-all-demos --iterations 3 --render
```

The Viewport library itself is resolved via `path: "../.."`, so changes to the
library are picked up without re-tagging.

> **Note:** SwiftPM prints a benign "conflicting identity for occtswiftviewport"
> warning here, because this package reaches Viewport two ways — directly via
> `path: "../.."` and transitively through `OCCTSwiftTools` (by URL). The path
> dependency wins (it's the local-override mechanism), the demo builds, and only
> this dev-only example is affected — never the published Viewport library. If a
> future SwiftPM escalates the warning to an error, switch this dependency to a
> URL pin (`from: "1.0.4"`); the demo would then build against released Viewport.
