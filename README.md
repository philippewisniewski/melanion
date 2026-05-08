# Melanion

A personal running coach and analytics app that lives entirely on your iPhone. Ask natural language questions about your training — pace trends, personal bests, recovery patterns, VO2 max over time — and get data-driven coaching answers backed by your full HealthKit history. No cloud, no subscription, no data leaving your device.

---

## What it does

Melanion queries your complete running history directly from Apple Health. When you ask a question in plain English ("What's my best 10km pace this year?" / "How does my sleep affect my next-day pace?"), the on-device model calls the right tools to fetch your data from HealthKit, then generates a coached narrative response — all using Apple Intelligence.

The result is a chat interface where every answer is grounded in your actual data. The app also surfaces proactive coaching moments as local notifications — new personal bests, streak milestones, trend improvements, and recovery nudges — without any cloud infrastructure.

---

## Architecture

The app is built around Apple's **Foundation Models Tool protocol**. A single `LanguageModelSession` receives the user's question and decides which tools to call to fetch the relevant HealthKit data, then synthesises a coaching response.

```
User question
    |
    v
+-----------------------------------+
|  LanguageModelSession             |
|  On-device LLM (Apple Intelligence)|
|  Instructions + athlete profile   |
+-----------------------------------+
    |  (model decides which tools to call)
    v
+-----------------------------------+
|  Tools (4 conformances)           |
|  RunHistoryTool                   |
|  TrainingTrendsTool               |
|  RecoveryTool                     |
|  RouteTool                        |
+-----------------------------------+
    |  (query HealthKit directly)
    v
+-----------------------------------+
|  HealthKit                        |
|  HKWorkout, HKWorkoutRoute,      |
|  HRV, sleep, VO2 max, etc.       |
+-----------------------------------+
    |  (formatted string results)
    v
+-----------------------------------+
|  Model synthesises response       |
|  Streaming text generation        |
+-----------------------------------+
    |
    v
Chat bubble (streamed text)
```

The model autonomously decides which tools to invoke based on the question, removing the need for a separate classifier step. Tool output is returned as concise formatted strings to stay within the 4,096 token context window.

---

## Apple Frameworks & APIs

### HealthKit
The primary data source. Melanion reads directly from Apple Health on every query — no local database, no caching layer. Data accessed includes:
- **HKWorkout** — running sessions with duration, distance, heart rate, and biomechanical form metrics (ground contact time, vertical oscillation, stride length, running power)
- **HKWorkoutRoute / HKWorkoutRouteQuery** — GPS polylines and per-km elevation data for each run
- **Recovery metrics** — HRV, resting heart rate, VO2 max, sleep duration, respiratory rate, wrist temperature, SpO2, and one-minute heart rate recovery — fetched across three time windows per run (night before, run day, day after)

### Foundation Models
Apple's on-device large language model, powering the chat pipeline via the Tool protocol. See the [Foundation Models](#foundation-models) section below for a deep dive.

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
- A downsampled polyline stored as a JSON-encoded `[[Double]]` array (<=200 points per run) for map rendering

---

## Swift Language Concepts

### Swift 6 Strict Concurrency
The app is compiled with Swift 6 and full strict concurrency checking. Every type that crosses actor boundaries must be `Sendable`. Key patterns used throughout:

- **`@MainActor`** on all `@Observable` view models and services — UI state is always mutated on the main actor
- **`nonisolated`** on pure computation functions (`computeStreak`) that don't touch shared state
- **`@unchecked Sendable`** on `MilestoneDetector` — a singleton accessed from background tasks, where internal state is protected by structured concurrency
- **`nonisolated(unsafe)`** on `BundledContext._biomechanicsReference` — a write-once lazy cache, safe because the write is idempotent

### Observation Framework (`@Observable`)
All view models use the `@Observable` macro introduced in iOS 17, replacing `ObservableObject` / `@Published`. This means:
- No explicit `@Published` needed — every stored property automatically triggers view updates
- `@Bindable` used in onboarding views to create two-way bindings into the shared `OnboardingViewModel`
- Services injected into the SwiftUI environment as plain `@Observable` objects, read with `@Environment(ServiceType.self)`

### Structured Concurrency
- **`async/await`** throughout — no completion handlers or Combine
- **`AsyncSequence` iteration** (`for try await snapshot in stream`) for streaming LLM responses
- **`withCheckedContinuation`** / **`withCheckedThrowingContinuation`** to bridge legacy callback-based HealthKit queries into the async/await world

### Tool Protocol
The `Tool` protocol from Foundation Models is the core abstraction powering the data layer. Each tool defines a `@Generable` `Arguments` type that the model fills in, and a `call(arguments:)` method that queries HealthKit and returns a formatted string:

```swift
struct RunHistoryTool: Tool {
    let name = "getRunHistory"
    let description = "Fetch running workouts with filtering and sorting"

    @Generable
    struct Arguments {
        @Guide(description: "recent, week, month, year, or all")
        var timeframe: String
        @Guide(description: "Max runs to return", .range(1...20))
        var count: Int
        @Guide(description: "date, pace, distance, duration, or elevation")
        var sortBy: String
    }

    func call(arguments: Arguments) async throws -> String {
        let workouts = try await HealthKitWorkoutFetcher().fetchRunningWorkouts()
        // Filter by timeframe, sort, take count, format as concise string
        return formatted
    }
}
```

Four tools cover the full query surface — `RunHistoryTool`, `TrainingTrendsTool`, `RecoveryTool`, and `RouteTool` — consolidating what was previously 25 separate SQL queries.

---

## Foundation Models

Foundation Models is Apple's framework for accessing the on-device large language model that powers Apple Intelligence. Introduced in iOS 26, it provides a Swift-native API for text generation, structured output, and tool use — all running locally on A17 Pro / M1 hardware or later, with no network calls.

### Why on-device?
- **Privacy** — your training data, health metrics, and questions never leave your iPhone
- **No latency** — no round-trip to a server; responses start immediately
- **No cost** — no API keys, no per-token billing
- **Offline** — works on a run with no signal

### `LanguageModelSession`
The core inference object. Each session maintains its own conversation history, eliminating the need for manual turn management. Melanion creates a single session per conversation with tools and instructions:

```swift
let session = LanguageModelSession(
    tools: [RunHistoryTool(), TrainingTrendsTool(), RecoveryTool(), RouteTool()],
    instructions: "You are Melanion, a running coach. Use tools to fetch the user's HealthKit data before answering."
)
```

Tools are passed at session creation. The model autonomously decides which tools to call based on the user's question — no classifier step needed.

### `@Generable` — Structured Output
The `@Generable` macro constrains the model's output to an exact Swift type. In Melanion, it's used for tool arguments — the model fills in typed parameters that drive HealthKit queries:

```swift
@Generable
struct Arguments {
    @Guide(description: "week, month, or season")
    var period: String
    @Guide(description: "pace, distance, volume, frequency, vo2max, hr, or streak")
    var metric: String
}
```

`@Guide` steers the model semantically within the structural constraint, keeping descriptions short to conserve tokens.

### `streamResponse` — Live Rendering
The chat uses streaming so the assistant bubble starts filling in immediately:

```swift
let stream = service.session.streamResponse(to: question)
for try await snapshot in stream {
    // each snapshot is a FULL SNAPSHOT of the text so far — replace, don't append
    messages[idx].content = snapshot.content
}
```

`streamResponse(to:)` returns a `ResponseStream<String>` — an `AsyncSequence` where each element is the full generated text so far, not an incremental token delta. The UI replaces the bubble content on each yield, giving a typewriter effect.

### Context Window
The model has a **4,096 token** combined input/output context window. Melanion is designed to stay within this:
- Instructions (role + athlete profile): ~100 tokens
- Tool definitions (4 tools): ~200 tokens
- Tool output (formatted HealthKit data): typically 100-300 tokens
- User question: ~20-50 tokens
- Response: ~200-400 tokens

Tools return concise formatted strings rather than complex structured types to minimize token consumption. If a request exceeds the context window, `LanguageModelSession.GenerationError` is thrown and the user sees a helpful error message.

### `prewarm` — Faster First Response
`prewarm(promptPrefix:)` is called when the chat view appears, pre-processing instructions and tool schemas so the first response starts faster:

```swift
session.prewarm(promptPrefix: "Analyze my")
```

### Hardware Requirements
Foundation Models requires:
- iPhone 15 Pro / iPhone 15 Pro Max or later (A17 Pro chip)
- iPad with M1 chip or later
- Apple Intelligence enabled in Settings > Apple Intelligence & Siri
- iOS 26+

Melanion checks `SystemLanguageModel.default.availability` at the app root and shows a blocking `IntelligenceUnavailableView` with actionable guidance if the requirement isn't met.

---

## Data Layer

There is no local database. HealthKit is the single source of truth — every tool call queries Apple Health directly via `HealthKitWorkoutFetcher`, `HealthKitRecoveryFetcher`, and `HealthKitRouteFetcher`.

| Fetcher | Purpose |
|---|---|
| `HealthKitWorkoutFetcher` | Running workouts — pace, distance, HR, form metrics |
| `HealthKitRecoveryFetcher` | Recovery data — HRV, sleep, resting HR, VO2 max across three time windows per run |
| `HealthKitRouteFetcher` | GPS routes — per-km splits, elevation gain/loss, polylines |

On first launch, the onboarding flow verifies HealthKit access and reports how many runs are available. No import or seeding step is required.

---

## Notifications

Melanion delivers proactive coaching moments as **local notifications** — no push certificates, no server, no cloud. Everything is handled by `UNUserNotificationCenter` on-device.

### When notifications fire

Notifications are evaluated by `MilestoneDetector.evaluateAfterSync()`, which queries HealthKit directly for workout and recovery data. Each fired event is tracked in UserDefaults so it never fires more than once.

| Category | Trigger |
|---|---|
| **Run complete** | Any run with a start time within the last 24 hours |
| **All-time pace PB** | Latest run is the fastest ever |
| **Distance bracket PB** | Fastest 5 km, 10 km, half-marathon, or marathon |
| **Longest run ever** | New all-time distance record |
| **Streak milestones** | 7, 14, 30, 50, and 100 consecutive running days |
| **Run count milestones** | 10th, 25th, 50th, 100th, and 250th total run |
| **Welcome back** | First run after a gap of more than 14 days |
| **Weekly pace trend** | Average pace improved >3% vs the prior 4-week window — scheduled for next Monday at 08:00 |
| **Recovery nudge** | Hard run (high HR, >15 km, or >200 m elevation) followed by HRV dropping >15% below baseline — scheduled for the next morning at 07:00 |

### Architecture

```
MilestoneDetector.evaluateAfterSync()
    |  (queries HealthKit directly)
    +-- fetch workouts via HealthKitWorkoutFetcher
    +-- fetch recovery via HealthKitRecoveryFetcher
    +-- detect events, dedup via UserDefaults
    +-- return [NotificationPayload]
    |
    v
NotificationService.schedule(_:)
    |  (UNUserNotificationCenter)
    v
Local notification delivered when app is backgrounded
```

**`NotificationService`** is a singleton registered as `UNUserNotificationCenterDelegate` at app launch. The `willPresent` delegate method suppresses banners while the app is in the foreground.

### User settings

All five notification categories are individually toggle-able in **Settings > Notifications**. The OS permission sheet is requested only when the user enables their first toggle, never at cold launch.

---

## Requirements

- Xcode 26+
- iOS 26+ deployment target
- iPhone 15 Pro or later / iPad M1 or later
- Apple Intelligence enabled
- HealthKit data (running workouts)
