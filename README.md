# Melanion

A personal running coach and analytics app that lives entirely on your iPhone. Ask natural language questions about your training — pace trends, personal bests, recovery patterns, VO2 max over time — and get data-driven coaching answers backed by your full HealthKit history. No cloud, no subscription, no data leaving your device.

---

## What it does

Melanion queries your complete running history directly from Apple Health. When you ask a question in plain English, a `DataRetriever` classifies the intent, fetches the relevant HealthKit data, and injects it as structured key-value pairs into the prompt. The on-device foundation model generates a guided `@Generable` response type, and Swift code formats the output into natural language prose — all using Apple Intelligence.

The app also surfaces proactive coaching moments as local notifications — new personal bests, streak milestones, trend improvements, and recovery nudges — without any cloud infrastructure.

---

## Architecture

```
User question
    |
    v
+-----------------------------------+
|  DataRetriever.classify()         |
|  Rule-based intent classification |
|  (lastRun, lastFew, longestRun,   |
|   trends, recovery, general, etc) |
+-----------------------------------+
    |
    v
+-----------------------------------+
|  DataRetriever.retrieve(for:)     |
|  Fetches HealthKit data           |
|  Formats as structured key-value  |
|  (distance_km: 5.20, pace_sec:   |
|   312, start_hour: 17, etc.)      |
+-----------------------------------+
    |
    v
+-----------------------------------+
|  LanguageModelSession             |
|  Apple FM (~3B, 2-bit quantised)  |
|  streamResponse(to:generating:)   |
+-----------------------------------+
    |  (per-intent @Generable type)
    v
+-----------------------------------+
|  @Generable struct                |
|  SingleRunResponse                |
|  RunListResponse / RunListItem     |
|  TrendResponse                    |
|  RecoveryResponse                 |
|  GeneralResponse                  |
+-----------------------------------+
    |  (PartiallyGenerated stream)
    v
+-----------------------------------+
|  Format function (Swift)          |
|  Converts struct → natural prose  |
|  "Your run on 22 May covered      |
|   3.9 km."                        |
+-----------------------------------+
    |
    v
Chat bubble (streamed text)
```

The model never decides which data to fetch — `DataRetriever.classify()` handles that in Swift using rule-based keyword matching. The model's only job is extracting values from structured data into typed `@Generable` fields. This eliminates the Tool protocol's reliability problems (model forgetting it has tools, calling wrong tools, hallucinating data).

---

## Apple Frameworks & APIs

### HealthKit
The primary data source. Melanion reads directly from Apple Health on every query — no local database, no caching layer. Data accessed includes:
- **HKWorkout** — running sessions with duration, distance, heart rate, and biomechanical form metrics (ground contact time, vertical oscillation, stride length, running power)
- **HKWorkoutRoute / HKWorkoutRouteQuery** — GPS polylines and per-km elevation data for each run
- **Recovery metrics** — HRV, resting heart rate, VO2 max, sleep duration, respiratory rate, wrist temperature, SpO2, and one-minute heart rate recovery — fetched across three time windows per run (night before, run day, day after)

### Foundation Models
Apple's on-device large language model, accessed via `streamResponse(to:generating:)` for guided structured output. See the [Foundation Models](#foundation-models) section below for a deep dive.

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

### Data Flow
The `DataRetriever` handles all HealthKit interaction in Swift. The model never fetches data — it only extracts values from data already in the prompt:

```swift
let intent = retriever.classify(question)
let (data, precomputed) = await retriever.retrieve(for: question)
let prompt = "\(data)\n\n\(precomputed)\n\nQuestion: \(question)"

let stream = session.streamResponse(
    to: prompt,
    generating: SingleRunResponse.self,
    includeSchemaInPrompt: true
)
for try await snapshot in stream {
    let text = formatSingleRun(snapshot.content)
    message.content = text
}
```

---

## Foundation Models

Foundation Models is Apple's framework for accessing the on-device large language model that powers Apple Intelligence. Introduced in iOS 26, it provides a Swift-native API for text generation, structured output, and tool use — all running locally on A17 Pro / M1 hardware or later, with no network calls.

### Why on-device?
- **Privacy** — your training data, health metrics, and questions never leave your iPhone
- **No latency** — no round-trip to a server; responses start immediately
- **No cost** — no API keys, no per-token billing
- **Offline** — works on a run with no signal

### `LanguageModelSession`
Melanion creates a fresh session per question (no conversation history) to avoid context window issues:

```swift
let session = LanguageModelSession(instructions: systemPrompt)
```

The system prompt is short (~5 lines) and focuses on data fidelity: "You MUST use ONLY the data provided."

### `@Generable` — Structured Output
The `@Generable` macro constrains the model's output to an exact Swift type. Melanion uses five response types, one per intent group:

```swift
@Generable(description: "Summary of a single run with all available metrics")
struct SingleRunResponse {
    var date: String
    var distanceKm: Double
    var paceSeconds: Int
    var durationSeconds: Int
    var heartRateBpm: Int?
    var caloriesKcal: Int?
    var elevationMetres: Int?
    var cadenceSpm: Int?
}
```

`@Guide` descriptions steer the model semantically within the structural constraint. The schema is included in every prompt (`includeSchemaInPrompt: true`) since each question uses a fresh session.

### `streamResponse` with `PartiallyGenerated`
The chat uses streaming with guided generation so the assistant bubble starts filling in immediately:

```swift
let stream = service.session.streamResponse(
    to: prompt,
    generating: SingleRunResponse.self,
    includeSchemaInPrompt: true
)
for try await snapshot in stream {
    // snapshot.content is a PartiallyGenerated struct — all fields are Optional
    // Our format function handles nil gracefully as fields populate
    messages[idx].content = formatSingleRun(snapshot.content)
}
```

### Context Window
The model has a **4,096 token** combined input/output context window. Melanion is designed to stay within this:
- System instructions: ~100 tokens
- Data (structured key-value, 5-10 workouts): 200-800 tokens
- Precomputed stats: ~100 tokens
- @Generable schema: ~50-100 tokens
- User question: ~20-50 tokens
- Response: ~200-400 tokens

### `prewarm` — Faster First Response
`prewarm(promptPrefix:)` is called when the chat view appears, pre-processing instructions so the first response starts faster.

### Hardware Requirements
Foundation Models requires:
- iPhone 15 Pro / iPhone 15 Pro Max or later (A17 Pro chip)
- iPad with M1 chip or later
- Apple Intelligence enabled in Settings > Apple Intelligence & Siri
- iOS 26+

Melanion checks `SystemLanguageModel.default.availability` at the app root and shows a blocking `IntelligenceUnavailableView` with actionable guidance if the requirement isn't met.

---

## Data Layer

There is no local database. HealthKit is the single source of truth — `DataRetriever` queries Apple Health directly via `HealthKitWorkoutFetcher` and `HealthKitRecoveryFetcher`.

| Fetcher | Purpose |
|---|---|
| `HealthKitWorkoutFetcher` | Running workouts — pace, distance, HR, form metrics, start hour |
| `HealthKitRecoveryFetcher` | Recovery data — HRV, sleep, resting HR, VO2 max across three time windows per run |

On first launch, the onboarding flow verifies HealthKit access and reports how many runs are available.

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
