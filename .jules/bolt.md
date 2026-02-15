## 2025-05-15 - [Optimize HubSection list and DPR lookups]
**Learning:** Providing `itemExtent` to `ListView.builder` for horizontal hubs with uniform items drastically reduces layout overhead. Additionally, using specialized `MediaQuery` selectors like `devicePixelRatioOf(context)` prevents unnecessary global rebuilds on safe area or window size changes.
**Action:** Always check for fixed-size list items and prefer specific MediaQuery selectors over `MediaQuery.of(context)`.
