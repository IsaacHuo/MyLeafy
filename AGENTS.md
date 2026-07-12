## Project Context

This is MyLeafy, an iOS campus app.

Core stack:
- SwiftUI
- SwiftData
- URLSession
- Supabase
- Swift Package Manager

Minimum iOS target:
- iOS 17+

Before changing code:
- Use liquid glass effects if the device is iOS 26+.
- Inspect existing SwiftUI patterns first.
- Do not introduce heavy architecture unless needed.
- Keep campus features stable and user-facing behavior predictable.

Principles:

1. **Fail Fast / No Silent Failures**
   Do not swallow errors, hide failures, or add fallback logic that masks real problems. When something breaks, surface it clearly.

2. **Fix Root Causes, Not Symptoms**
   Do not cover bugs with small patches, special cases, or temporary workarounds. Find the real cause and fix it properly.

3. **Make Debugging Possible**
   Critical paths must have enough logging, tracing, or observable state to diagnose failures. When information is insufficient, add instrumentation instead of pretending the issue is fixed.

4. **Keep Documentation in Sync**
   When the project’s core stack, architecture, or product direction changes, update `agents.md`. Documentation must evolve with the code and remain the single source of truth.

5. **Do Not Break Mainline**
   Create a separate branch before large refactors, risky changes, or experiments. Keep the main branch stable and releasable.
