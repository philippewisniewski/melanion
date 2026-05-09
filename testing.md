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
