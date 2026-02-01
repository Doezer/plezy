## 2026-02-01 - Optimize Rebuilds with Specialized MediaQuery Selectors
**Learning:** Using `MediaQuery.of(context)` causes a widget to rebuild whenever ANY property in `MediaQueryData` changes (e.g., keyboard appearing/disappearing, orientation change, padding changes). For widgets that only need specific properties like `devicePixelRatio` or `size`, using specialized selectors like `MediaQuery.devicePixelRatioOf(context)` or `MediaQuery.sizeOf(context)` significantly reduces unnecessary rebuilds.
**Action:** Always prefer `MediaQuery.sizeOf(context)`, `MediaQuery.paddingOf(context)`, and `MediaQuery.devicePixelRatioOf(context)` over the generic `MediaQuery.of(context)` in performance-critical widgets.

## 2026-02-01 - Bypassing LayoutBuilder for Explicit Dimensions
**Learning:** `LayoutBuilder` adds overhead by requiring a layout pass to determine constraints before building. If a widget's dimensions are already known (e.g., provided as finite `width` and `height` properties), bypassing `LayoutBuilder` reduces widget tree depth and eliminates the builder execution overhead.
**Action:** In widgets like `PlexOptimizedImage`, check for finite explicit dimensions and skip `LayoutBuilder` when they are available.
