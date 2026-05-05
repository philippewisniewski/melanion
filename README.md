# Melanion

A personal running coach and analytics app that lives entirely on your iPhone. Ask natural language questions about your training — pace trends, personal bests, recovery patterns, VO₂ max over time — and get data-driven coaching answers backed by your full HealthKit history. No cloud, no subscription, no data leaving your device.

---

## What it does

Melanion reads your complete running history from Apple Health and stores it in a local SQLite database. When you ask a question in plain English ("What's my best 10km pace this year?" / "How does my sleep affect my next-day pace?"), the app routes it to the right SQL query, executes it, and generates a coached narrative response — all on-device using Apple Intelligence.

The result is a chat interface where every answer is grounded in your actual data, formatted as text with a typed data card below it. The app also surfaces proactive coaching moments as local notifications — new personal bests, streak milestones, trend improvements, and recovery nudges — without any cloud infrastructure.

---

## Architecture

The app is built around a **two-call LLM pipeline**:

```
User question
    │
    ▼
┌─────────────────────────────────┐
│  Call 1 — Classifier            │
│  @Generable structured output   │
│  Routes question → SQL query    │
└─────────────────────────────────┘
    │  (QueryDefinition + params)
    ▼
┌─────────────────────────────────┐
│  SQL Execution (GRDB / SQLite)  │
│  25 named queries               │
│  Returns [[String: Any?]] rows  │
└─────────────────────────────────┘
    │  (Markdown table)
    ▼
┌─────────────────────────────────┐
│  Call 2 — Responder             │
│  Streaming text generation      │
│  Coaching narrative + card      │
└─────────────────────────────────┘
    │
    ▼
Chat bubble + typed data card
```

This separation keeps the classifier deterministic (structured output constrains the model to valid query names) and lets the responder focus purely on generating natural language without needing to reason about data retrieval.

---

## Apple Frameworks & APIs

### HealthKit
Used to read the complete running history from Apple Health. Melanion accesses:
- **HKWorkout** — running sessions with duration, distance, heart rate, and biomechanical form metrics (ground contact time, vertical oscillation, stride length, running power)
- **HKWorkoutRoute / HKWorkoutRouteQuery** — GPS polylines and per-km elevation data for each run
- **Recovery metrics** — HRV, resting heart rate, VO₂ max, sleep duration, respiratory rate, wrist temperature, SpO₂, and one-minute heart rate recovery — fetched across three time windows per run (night before, run day, day after)

All data is read once on first launch and stored locally in GRDB. Subsequent launches go straight to chat.

### Foundation Models
Apple's on-device large language model, powering both pipeline calls. See the [Foundation Models](#foundation-models) section below for a deep dive.

### Swift Charts
Powers the `TrendCard` component — line and area charts for trends like VO₂ max over time, monthly training volume, resting heart rate, and sleep-vs-pace correlation. The Y axis is pace-aware: it formats raw `Int` seconds as `MM:SS/km` strings rather than numbers.

### SwiftUI
The entire UI is SwiftUI-only — no storyboards, no UIKit views. Notable patterns used:
- `safeAreaInset(edge: .bottom)` for the chat input bar, ensuring it lifts with the keyboard without hardcoded padding
- `.ignoresSafeArea(.keyboard)` on the outer container so the background fills edge-to-edge
- `NavigationStack` as the root container for the main app flow
- `@AppStorage` for the onboarding completion flag
- `fullScreenCover` for the onboarding screens

### CoreLocation
`CLLocation` points are fetched from `HKWorkoutRoute` and processed to compute:
- Per-km split times (elapsed time at each distance milestone)
- Elevation gain and loss per km segment
- Total route elevation gain
- A downsampled polyline stored as a JSON-encoded `[[Double]]` array (≤200 points per run) for map rendering

---

## Swift Language Concepts

### Swift 6 Strict Concurrency
The app is compiled with Swift 6 and full strict concurrency checking. Every type that crosses actor boundaries must be `Sendable`. Key patterns used throughout:

- **`@MainActor`** on all `@Observable` view models and services — UI state is always mutated on the main actor
- **`nonisolated`** on pure computation functions (`computeStreak`, `computeGAP`) that don't touch shared state
- **`@unchecked Sendable`** on `ChatMessage` — justified because it contains `[String: Any?]` (inherently not `Sendable`) but is only ever accessed on `@MainActor`
- **`nonisolated(unsafe)`** on `BundledContext._biomechanicsReference` — a write-once lazy cache, safe because the write is idempotent

### Observation Framework (`@Observable`)
All view models use the `@Observable` macro introduced in iOS 17, replacing `ObservableObject` / `@Published`. This means:
- No explicit `@Published` needed — every stored property automatically triggers view updates
- `@Bindable` used in onboarding views to create two-way bindings into the shared `OnboardingViewModel`
- Services injected into the SwiftUI environment as plain `@Observable` objects, read with `@Environment(ServiceType.self)`

### Structured Concurrency
- **`async/await`** throughout — no completion handlers or Combine
- **`AsyncStream<String>`** bridges the Foundation Models `ResponseStream` to the UI layer
- **`AsyncSequence` iteration** (`for try await partial in stream`) for streaming LLM responses
- **`Task { @MainActor in }`** inside `ResponderPipeline` to satisfy actor isolation when accessing the `@MainActor`-isolated `LanguageModelService.responderSession`
- **`withCheckedContinuation`** / **`withCheckedThrowingContinuation`** to bridge legacy callback-based HealthKit queries into the async/await world

### Protocol-Oriented Design
`QueryDefinition` is the core protocol powering the data layer:

```swift
protocol QueryDefinition: Sendable {
    var name: String { get }        // identifier — used by classifier
    var description: String { get } // natural language — used in classifier prompt
    var format: ResponseFormat { get }
    func execute(db: Database, params: [String: String]) throws -> [QueryRow]
}
```

All 25 query types conform to this protocol. `QueryRegistry.all` is the single source of truth — adding a new query automatically makes it available to the classifier prompt, the `@Generable` enum, and the UI card system.

### Swift Testing
The `MelanionTests` target uses the Swift Testing framework (`import Testing`, `@Test`, `#expect`) introduced in Xcode 16. The `DatabaseMigrationTests` suite runs the full GRDB migrator against an in-memory `DatabaseQueue` and asserts every table and column exists — without touching the device's actual database.

---

## Foundation Models

Foundation Models is Apple's framework for accessing the on-device large language model that powers Apple Intelligence. Introduced in iOS 26, it provides a Swift-native API for text generation, structured output, and tool use — all running locally on A17 Pro / M1 hardware or later, with no network calls.

### Why on-device?
- **Privacy** — your training data, health metrics, and questions never leave your iPhone
- **No latency** — no round-trip to a server; responses start immediately
- **No cost** — no API keys, no per-token billing
- **Offline** — works on a run with no signal

### `LanguageModelSession`
The core inference object. Each session maintains its own conversation history, eliminating the need for manual turn management. Melanion uses two distinct session strategies:

```swift
// Classifier — fresh session per call, no instructions, no history needed
func classifierSession() -> LanguageModelSession {
    LanguageModelSession()
}

// Responder — persistent session, instructions set once, history accumulates
private func makeResponderSession(profile: UserProfile) -> LanguageModelSession {
    LanguageModelSession {
        SystemPromptBuilder.build(profile: profile)
    }
}
```

The classifier gets a fresh session on every call so prior conversation context never contaminates query routing. The responder reuses a single session so the model maintains awareness of the conversation history across turns.

### `@Generable` — Structured Output
The `@Generable` macro is the most powerful feature used in Melanion. Applied to a Swift `struct` or `enum`, it generates a `GenerationSchema` that constrains the model's output to that exact type — no JSON parsing, no regex, no temperature tuning.

```swift
@Generable
enum QueryName: String, Codable, CaseIterable {
    case recentRuns         = "recent_runs"
    case personalBest       = "personal_best"
    case vo2MaxTrend        = "vo2_max_trend"
    // ... 25 cases total
}

@Generable
struct QueryRouting {
    @Guide(description: "Select the query that best matches the user's question.")
    var query: QueryName

    @Guide(description: "Parameters required by the query. Empty dictionary if none needed.")
    var params: [String: String]
}
```

When the classifier calls `session.respond(to: prompt, generating: QueryRouting.self, options: GenerationOptions(sampling: .greedy))`, the model is **structurally constrained** to produce a valid `QueryName` case. It is impossible for it to hallucinate a query name that doesn't exist in the registry.

`@Guide` steers the model semantically within the structural constraint. `GenerationOptions(sampling: .greedy)` makes the output deterministic — equivalent to temperature 0.

### `streamResponse` — Live Rendering
The responder uses streaming so the assistant bubble starts filling in immediately rather than waiting for the full response:

```swift
let stream = service.responderSession.streamResponse(to: userTurn)
for await partial in stream {
    // each partial is a FULL SNAPSHOT of the text so far — replace, don't append
    messages[idx].content = partial
}
```

`streamResponse(to:)` returns a `LanguageModelSession.ResponseStream<String>` — an `AsyncSequence` where each element is the full generated text so far, not an incremental token delta. The UI replaces the bubble content on each yield, giving a typewriter effect.

### `Instructions` — System Prompts
Session instructions are set once at session creation using a result-builder closure:

```swift
LanguageModelSession {
    "You are Melanion, a personal running coach and analyst."
    "Your athlete: \(profile.name), goal: \(profile.goal.rawValue)"
    // biomechanics reference, format hints...
}
```

The format hint (how the model should structure its answer — single stat, numbered list, trend description, or detailed breakdown) is injected into each **user turn** rather than the session instructions. This keeps the persistent session reusable across queries with different response formats without rebuilding it.

### Context Window
The model has a **4,096 token** combined input/output context window. Melanion is designed to stay within this:
- System prompt (role + profile + biomechanics reference): ~350 tokens
- Markdown table from SQL query: typically 100–500 tokens depending on result size
- Format hint + user question: ~50 tokens
- Response: ~200–400 tokens

If a query produces a table that would exceed the context window, `LanguageModelSession.GenerationError.exceededContextWindowSize` is thrown and the user sees "Your data was too large to process. Try a more specific question."

### Hardware Requirements
Foundation Models requires:
- iPhone 15 Pro / iPhone 15 Pro Max or later (A17 Pro chip)
- iPad with M1 chip or later
- Apple Intelligence enabled in Settings → Apple Intelligence & Siri
- iOS 26+

Melanion checks `SystemLanguageModel.default.availability` at the app root and shows a blocking `IntelligenceUnavailableView` with actionable guidance if the requirement isn't met.

---

## Data Layer

**GRDB** (an SQLite wrapper for Swift) stores all run data in a local database at `Application Support/melanion.sqlite`. Three tables:

| Table | Purpose |
|---|---|
| `runs` | One row per workout — pace, distance, HR, form metrics, GPS metadata |
| `recovery` | Three rows per run — HRV, sleep, resting HR across night_before / run_day / day_after |
| `route_splits` | Per-km split times and elevation for runs with GPS data |
| `notified_milestones` | One row per fired notification event — prevents any milestone firing more than once across re-seeds |

The schema mirrors the original TypeScript `running-agent` exactly, enabling the same 25 SQL queries to work without translation. All column names are snake_case; GRDB's `DatabaseColumnDecodingStrategy.convertFromSnakeCase` maps them automatically to camelCase Swift properties.

---

## Notifications

Melanion delivers proactive coaching moments as **local notifications** — no push certificates, no server, no cloud. Everything is handled by `UNUserNotificationCenter` on-device, consistent with the app's zero-infrastructure philosophy.

### When notifications fire

Notifications are evaluated inside a single GRDB write transaction at the end of every HealthKit sync (`MilestoneDetector.evaluateAfterSync()`). Each event writes a row to `notified_milestones` so it never fires more than once, even across re-seeds.

| Category | Trigger |
|---|---|
| **Run complete** | Any run with a start time within the last 24 hours |
| **All-time pace PB** | Sync produces a new fastest-ever run |
| **Distance bracket PB** | Fastest 5 km, 10 km, half-marathon, or marathon |
| **Longest run ever** | New all-time distance record |
| **Streak milestones** | 7, 14, 30, 50, and 100 consecutive running days |
| **Run count milestones** | 10th, 25th, 50th, 100th, and 250th total run |
| **Welcome back** | First run after a gap of more than 14 days |
| **Weekly pace trend** | Average pace improved >3% vs the prior 4-week window — scheduled as a `UNCalendarNotificationTrigger` for next Monday at 08:00 |
| **Recovery nudge** | Hard run (high HR, >15 km, or >200 m elevation) followed by HRV dropping >15% below the 30-day baseline — scheduled for the next morning at 07:00 |

### Architecture

```
SeedingPipeline.seed()
    │  (after successful DB write)
    ▼
MilestoneDetector.evaluateAfterSync()
    │  (single GRDB write transaction)
    ├─ query runs + notified_milestones
    ├─ detect events, mark keys as fired
    └─ return [NotificationPayload]
    │
    ▼
NotificationService.schedule(_:)
    │  (UNUserNotificationCenter)
    ▼
Local notification delivered when app is backgrounded
```

**`NotificationService`** is a singleton registered as `UNUserNotificationCenterDelegate` at app launch. The `willPresent` delegate method suppresses banners while the app is in the foreground — the user is already in the app, so there's no need to interrupt them.

### User settings

All five notification categories are individually toggle-able in **Settings → Notifications**. The OS permission sheet is requested only when the user enables their first toggle, never at cold launch.

---

## Requirements

- Xcode 26+
- iOS 26+ deployment target
- iPhone 15 Pro or later / iPad M1 or later
- Apple Intelligence enabled
- HealthKit data (running workouts)
