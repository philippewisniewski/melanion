# Tool Validation Testing — Issue #23

**Date:** 2026-05-09
**Device:** iPhone (physical device)
**Architecture:** Foundation Models Tool protocol (4 tools, HealthKit-direct)

---

## RunHistoryTool — `getRunHistory`

| # | Question | Result | Notes |
|---|---|---|---|
| 1 | "Show me my last 5 runs" | PASS | Returns 5 runs with date, distance, pace, duration, HR, calories, cadence. Data coherent and correctly sorted by date. |
| 2 | "What's my fastest run ever?" | PASS | Returns 20 May, 4:50/km, 7.2km, 34m41s. Concise single-run response. |
| 3 | "What's my longest run ever?" | PASS | Returns 14 Feb, 20.7km, 5:34/km, 1h55m. Consistent with #4 top result. |
| 4 | "What are my top 5 longest runs?" | PASS | 5 runs sorted by distance descending (20.7, 20.0, 19.6, 17.8, 16.7km). Correct ordering. |
| 5 | "Which runs did I run faster than 4:30/km?" | MODEL ISSUE | Tool returned correct data. Model reported 4:50/km as faster than 4:30/km — incorrect reasoning. Lower pace number = faster. |
| 6 | "Show me runs where HR was above 170bpm" | PASS | Returns 27 Apr, 178bpm, 5:02/km, 11.5km. Correct filtering. |
| 7 | "What are my hilliest runs?" | PASS | Returns 27 Apr with 113m elevation gain. Model used RouteTool to include split-level elevation detail. |
| 8 | "Show my runs from this month" | PASS | Returns 1 run (19 Apr). Correct for the timeframe. |
| 9 | "What's my average pace and distance?" | PASS | 5:19/km avg pace, 12.5km avg distance. Reasonable aggregation. |
| 10 | "How many calories have I burned running?" | MODEL ISSUE | Gave total km (49.5) and averages but did not state the calorie total. Answered with distance/pace stats instead of calories. |

### UI Issues Found
- **Markdown not rendering** — `**bold**` markers showing as raw text. Fixed by switching to `AttributedString(markdown:)` in MessageBubble.
- **Keyboard dismissal** — No way to dismiss keyboard once raised. Fixed with `.scrollDismissesKeyboard(.interactively)`.

---

## TrainingTrendsTool — `getTrainingTrends`

| # | Question | Result | Notes |
|---|---|---|---|
| 11 | "How many km have I run each week over the last 3 months?" | PASS | Returns 5.5km avg/week. Concise, no markdown. Would be better with weekly breakdown. |
| 12 | "How many times a week do I usually run?" | PASS | Returns 1.2 times/week. Clean, direct. |
| 13 | "What's my current running streak?" | PASS | Returns 1 week. Plain text, direct answer. |
| 14 | "How has my pace trended this month?" | PASS | "Slightly decreasing" — correct direction but lacks specific pace numbers. |
| 15 | "How has my VO2 max changed over time?" | PASS | "Increased by 1.4 over the last 3 months." Specific with timeframe. |
| 16 | "How has my resting heart rate trended?" | PASS | "Decreased by 10 bpm over 3 months." Specific, actionable. |
| 17 | "When do I run best — morning or evening?" | MINOR | Answered about recovery not performance. Didn't compare pace/distance by time of day. Tool lacks time-of-day metric. |
| 18 | "How does my winter running compare to summer?" | FAIL | Generic response about cold weather. No actual data used — model didn't call the tool. Hallucinated general knowledge. |

---

## RecoveryTool — `getRecoveryData`

| # | Question | Result | Notes |
|---|---|---|---|
| 19 | "How was my recovery after my last run?" | PASS | "No data for recovery after your last run." Correct empty-state handling — user has limited recovery data. |
| 20 | "Show me my HRV and sleep over the last month" | MINOR | Returned HRV and sleep data (Jan 2025 vs Jan 2026). Reported HRV in "bpm" instead of "ms" — HRV is measured in milliseconds, not beats per minute. |
| 21 | "Does more sleep improve my pace?" | FAIL | Generic answer about sleep contributing to fitness/recovery. Model did not call the tool — answered from general knowledge instead of correlating actual sleep and pace data. |
| 22 | "What does my heart rate recovery look like?" | FAIL | "I don't have access to your HealthKit data." Model forgot it has tools available. Same class of issue as Q18. |

---

## RouteTool — `getRunRoute`

| # | Question | Result | Notes |
|---|---|---|---|
| 23 | "Show me the km splits from my last run" | FAIL | Returned summary only: "15.8km at 5:12/km". Did not show per-km splits. Model over-summarised tool output or tool didn't return split-level detail. |
| 24 | "How was my pacing on my last run?" | PASS | "Improved from 5:38/km to 5:02/km." Shows negative split pattern with specific numbers. Concise and useful. |
| 25 | "How does elevation affect my pace?" | MINOR | "Slight impact, slower paces at higher elevations." Directionally correct but no specific numbers. Same vagueness issue as Q14. |

---

## Model Limitations Log

Issues where the tool returned correct data but the model's reasoning was wrong. These need workarounds or prompt engineering.

### 1. Pace comparison logic (Q5)
**Problem:** Model reported 4:50/km as "faster than 4:30/km". In running, lower pace = faster (4:30 is faster than 4:50).
**Impact:** Any question involving pace thresholds or comparisons may get inverted answers.
**Potential workarounds:**
- Add a note to the system prompt: "Remember: lower pace (min/km) = faster. 4:00/km is faster than 5:00/km."
- Format tool output to include "(faster)" / "(slower)" labels
- Pre-filter in the tool itself when a pace threshold is detectable

### 2. Fastest 5K reasoning error (ad-hoc testing)
**Problem:** Asked "What was my fastest 5k?" and got a strange/incorrect response. Same root cause as Q5 — model doesn't reliably understand that lower pace = faster.
**Impact:** Any "fastest" query for distance brackets (5K, 10K, half-marathon) may return wrong results.
**Potential workarounds:**
- Same as Q5 — system prompt hint about pace direction
- Tool could pre-compute "fastest in bracket" and label it explicitly in output
- RunHistoryTool could add a distance bracket filter argument

### 3. Winter vs summer — no tool called (Q18)
**Problem:** Asked "How does my winter running compare to summer?" and got a generic answer about cold weather being challenging. Model did not call any tool — answered from general knowledge instead of HealthKit data.
**Impact:** Seasonal comparison questions may not use actual data at all.
**Potential workarounds:**
- Strengthen system prompt: "ALWAYS use tools before answering. Never answer from general knowledge."
- TrainingTrendsTool season metric may need clearer description so model knows to call it

### 4. Time-of-day not supported (Q17)
**Problem:** Asked "When do I run best — morning or evening?" and got a recovery-based answer instead of pace/performance comparison by time of day.
**Impact:** Time-of-day analysis questions can't be answered accurately.
**Potential workarounds:**
- RunHistoryTool output could include the hour of each run
- TrainingTrendsTool could add a time-of-day metric that groups runs by morning/afternoon/evening

### 5. Responses too vague — missing specific values and units (Q11, Q14, Q15)
**Problem:** Model over-summarises tool output. Says "slightly decreasing" instead of actual pace values, "increased by 1.4" without units (ml/kg/min). Runners need specific numbers to act on.
**Impact:** Trend and aggregate responses lack the precision needed to be useful coaching feedback.
**Potential workarounds:**
- Enrich tool output with units and comparison labels (e.g. "5:12/km, down from 5:24/km last month")
- Add explicit values with units in tool output so the model can't strip them
- System prompt could emphasise "always include specific numbers with units"
- Issue #28 (structured cards) will help by rendering data visually rather than relying on model text

### 6. Calorie question not answered directly (Q10)
**Problem:** Asked "How many calories have I burned running?" but got distance/pace summary without a calorie total.
**Impact:** Specific metric questions may get generic summaries instead of direct answers.
**Potential workarounds:**
- Ensure tool output includes calories prominently when present
- Add "activeCaloriesKcal" to the formatted output for each run
- Consider adding a calorie total line at the bottom of tool output

### 7. HRV units incorrect (Q20)
**Problem:** Model reported HRV in "bpm" (beats per minute) instead of "ms" (milliseconds). HRV is measured in milliseconds — bpm is for heart rate.
**Impact:** HRV-related responses may confuse users who know HRV is measured in ms, or mislead those who don't.
**Potential workarounds:**
- RecoveryTool output should explicitly label "HRV: 45ms" with the unit
- System prompt could clarify "HRV is measured in milliseconds (ms), not bpm"

### 8. Model forgets it has tools (Q18, Q22)
**Problem:** On two separate occasions the model either answered from general knowledge without calling a tool (Q18) or explicitly said "I don't have access to your HealthKit data" (Q22). Both times, the relevant tool was available.
**Impact:** Any question can potentially get a non-data-driven response if the model doesn't recognise it should call a tool.
**Potential workarounds:**
- Strengthen system prompt: "ALWAYS use tools before answering. Never answer from general knowledge. You have access to HealthKit data through your tools."
- Keep tool descriptions clear and broad so the model recognises more question types as tool-eligible
- May be a context window issue — later in a session the model may lose track of available tools

### 9. Correlation questions not data-driven (Q21)
**Problem:** Asked "Does more sleep improve my pace?" and got a generic answer about sleep and recovery. The model didn't correlate actual sleep duration with actual pace data from HealthKit.
**Impact:** Any "does X affect Y" correlation question may get textbook answers instead of personalised analysis.
**Potential workarounds:**
- RecoveryTool could pre-compute correlation metrics (e.g. avg pace on high-sleep nights vs low-sleep nights)
- System prompt hint: "For correlation questions, fetch both datasets and compare specific values"
- May need a dedicated analysis tool or cross-tool orchestration

### 10. Per-km splits not shown (Q23)
**Problem:** Asked "Show me the km splits from my last run" but got a one-line summary ("15.8km at 5:12/km") instead of per-km split data. The RouteTool is designed to return split-level detail.
**Impact:** Users asking for splits — a core running feature — get useless summaries instead of actionable per-km breakdowns.
**Potential workarounds:**
- Check RouteTool output format — ensure it explicitly lists each km split, not just averages
- Model may be over-summarising multi-line tool output to stay concise — system prompt could add "When asked for splits, show every split"
- Issue #28 (structured cards) would render splits as a table/chart rather than relying on the model's text

---

## Fixes Applied During Testing

| Fix | File | Description |
|---|---|---|
| Plain text system prompt | `SystemPromptBuilder.swift` | Added "Use plain text only — no markdown, no bold, no bullet points" to prevent raw markdown in responses |
| Keyboard dismissal | `ChatView.swift` | Added `.scrollDismissesKeyboard(.interactively)` to ScrollView |
| Xcode scheme missing | `project.yml` | Added scheme definition so simulator/device destinations appear |
| Prewarm type error | `LanguageModelService.swift` | Changed `"Analyze my"` to `Prompt("Analyze my")` |

---

## Raw Data Verification — 2026-05-09

Cross-referenced all test results against the raw Apple Health export (`export.xml`, 463MB, 59 real runs spanning Feb 2025 – Apr 2026) and 29 GPX route files in `workout-routes/`. Distance is stored in `WorkoutStatistics` child elements (miles, converted). HR, calories, and elevation come from `WorkoutStatistics` and `MetadataEntry` (`HKElevationAscended`). HR data is only present from May 2025 onward — earlier Strava-sourced runs have no HR statistics in the export.

---

### Individual Workout Queries — Verified Correct

The following model outputs were confirmed accurate against the raw export to within rounding:

| Test | Claim | Raw Data | Verdict |
|---|---|---|---|
| Q2 — fastest run | 20 May, 4:50/km, 7.2km, 34m41s | 7.17km, 34m41s, 4:50/km | **MATCH** |
| Q3 — longest run | 14 Feb, 20.7km, 5:34/km, 1h55m | 20.66km, 1h55m02s, 5:34/km | **MATCH** |
| Q4 — top 5 longest | 20.7 / 20.0 / 19.6 / 17.8 / 16.7km | All five confirmed to ±0.1km in correct order | **MATCH** |
| Q5 — HR >170bpm run | 27 Apr, 178bpm, 5:02/km, 11.5km | 178.4bpm, 5:02/km, 11.49km | **MATCH** (one of 29 qualifying runs — tool returned most recent) |
| Q6 — hilliest run value | 113m elevation on 27 Apr | HKMetadata=114m, GPX computed=112.6m | **MATCH ±1m** — but see bug below |

---

### Bug-Level Discrepancies — Tool Layer, Not Model

These are incorrect results where the raw data is unambiguous. The model is working with wrong tool output.

**Bug 1 — "Hilliest run" returns latest, not maximum elevation (Q7)**
- 27 Apr was returned with 113m gain
- Actual top runs by elevation: Feb 1 = 313m, Mar 22 = 313m, Oct 18 = 283m, Dec 25 = 282m
- 27 Apr ranks ~15th in the dataset — not the hilliest by any measure
- Root cause: `getRunHistory` is not sorting by `HKElevationAscended` descending; it appears to be returning the most recent run that has elevation data
- **Fix:** Sort by elevation descending when query intent is "hilliest". Do not conflate recency with maximum.

**Bug 2 — RouteTool "last run" resolves to wrong workout (Q23, Q24)**
- Tool returned Apr 19 (15.76km, 5:12/km) as the last run
- Actual last run is Apr 27 (11.49km, 5:02/km); GPX file `route_2026-04-27_4.20pm.gpx` exists on disk
- The Apr 24 pacing claim ("improved from 5:38 to 5:02/km") uses 5:02 which matches Apr 27, not Apr 19, suggesting the two tools resolved "last run" to different workouts — a consistency failure
- Root cause: `getRunRoute` is likely sorting GPX files alphabetically or using a different date field than `getRunHistory`
- **Fix:** Both tools must resolve "last run" against the same date sort key (workout `endDate` from HealthKit, not filesystem timestamp).

**Bug 3 — "This month" filter returns 1 of 5 April 2026 runs (Q8)**
- Tool returned 1 run (Apr 19) for "this month" (April 2026)
- Raw data has 5 runs in April 2026: Apr 8, 10, 19, 23, 27
- Root cause: likely an off-by-one or `<` vs `<=` boundary error in the month date range, or the filter is computing against the wrong reference date
- **Fix:** Audit the date range predicate for "this month" — ensure it spans the full calendar month, not a rolling 30-day window from the most recent run.

---

### Aggregate & Trend Data — Numbers Do Not Match Raw Export

These outputs are wrong and cannot be explained by rounding or windowing choices. The tool layer is computing over an incorrect or incomplete dataset.

| Test | Claim | Raw Data | Gap |
|---|---|---|---|
| Q9 — avg pace | 5:19/km | 5:35/km (all 59 runs); 5:33/km (May 2025+ only) | Off by ~14s/km; no plausible subset produces 5:19 |
| Q9 — avg distance | 12.5km | 11.3km (all runs); 11.5km (May 2025+) | Off by ~1km |
| Q10 — total km | ~49.5km (implied) | 666.8km total dataset | Matches only ~4 recent runs — severe windowing bug |
| Q15 — VO2 max +1.4 | Increased by 1.4 over 3 months | +0.26 (true 3-month window to test date); ~+1.8 (window ending at last run Apr 27) | Cannot reproduce +1.4 from any window |
| Q16 — resting HR -10bpm | Decreased by 10bpm over 3 months | Flat trend, 56–65bpm range; actual 3-month change = +2bpm | Opposite direction; no 10bpm decline in any window |

**Notes on calorie data (Q10):** Calories are absent from `WorkoutStatistics` for all Strava-sourced runs in the export (no `HKQuantityTypeIdentifierActiveEnergyBurned` child element). If the tool is reporting calories for these runs it is either computing an estimate or sourcing from somewhere other than Workout-level statistics. This should be documented in the tool.

**Notes on VO2 max:** 191 records in the export spanning Feb 2025 – May 2026. Values are stable in the 43–46 ml/kg/min range with no abrupt changes. The +1.4 figure does not correspond to any 3-month window against the test date. If `getTrainingTrends` uses the last run date as the window end (Apr 27) rather than the current date, the closest result is +1.77, still not +1.4. The metric computation in the tool needs to be audited.

**Notes on resting HR:** 255 records, stable in the 56–70bpm range throughout the 3-month window. No downward trend is present. The -10bpm claim is the largest factual discrepancy in the test suite and indicates either a faulty aggregation or the tool is selecting outlier records as window boundaries.

---

### What Is and Isn't a Model Problem

| Issue | Root Cause | Where to Fix |
|---|---|---|
| Pace direction confusion (Q5, ad-hoc) | Model reasoning | System prompt + tool-side pre-filtering |
| Vague summaries, missing units (Q14, Q15, Q25) | Model over-summarising | Enrich tool output with units and labels |
| Model doesn't call tool (Q18, Q21, Q22) | Model tool-awareness | System prompt; tool description breadth |
| HRV unit wrong — "bpm" instead of "ms" (Q20) | Tool output missing unit label | Add "ms" suffix to HRV values in `RecoveryTool` output |
| Hilliest run wrong (Q7) | Tool sort logic | Fix `getRunHistory` elevation sort |
| Wrong "last run" (Q23) | Tool date sort inconsistency | Align `getRunRoute` sort key with HealthKit `endDate` |
| "This month" returns 1 of 5 runs (Q8) | Tool date filter boundary | Fix month range predicate |
| Avg pace / distance / total km wrong (Q9, Q10) | Tool aggregation window | Audit `getTrainingTrends` date window and dataset scope |
| VO2 max +1.4 unverifiable (Q15) | Tool metric computation | Audit window end date and value selection logic |
| Resting HR -10bpm wrong (Q16) | Tool metric computation | Audit outlier handling and window boundaries |
