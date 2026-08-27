# Fine-Tuning Experiment & Findings — Bridging to Melanion

## Context

Melanion is an on-device running-analytics assistant. An early direction explored a
custom **fine-tuned** model (LFM2.5-230M, MLX, LoRA) to answer natural-language
running questions. That path was **superseded by Apple's on-device Foundation Model**
(`FoundationModels` / `SystemLanguageModel`) for the shipped app — but the fine-tuning
experiment produced concrete findings that directly shaped the app's architecture.

This document records **what we tested, the results, and how each finding maps to a
feature in the app**, so the research rationale isn't lost now that the pipeline is
archived.

## What we tested (MLX pipeline)

| Stage | File | Purpose |
|---|---|---|
| GPX parsing | `parse_gpx.py` | Parse GPX tracks → per-km splits, cumulative distance, elevation |
| Label generation | `generate_labels.py` | Synthesize (question, answer) training pairs from structured run data |
| Dataset assembly | `format_jsonl.py` | MLX chat-format JSONL; Running-only filter **86 → 74** examples |
| GPX coverage | — | **63 / 74** runs had a matching GPX file |
| Training | `train_lora.py` (MLX LoRA) | Training loss **4.66 → 0.64** |
| Deploy | `deploy_mlx.py` + `merge_adapter.py` + `test_merged.py` | Exported a **4-bit MLX model (~0.2 GB)** |

## Results

- **Mechanics validated:** the full MLX-native loop — data → LoRA → 4-bit deploy — works
  end to end on a Mac. The tooling is sound.
- **Quality not viable at this data scale:** with only **74 examples** the fine-tune
  **overfit** and produced **degenerate output (repetition / looping)**. The base
  LFM2.5-230M model produced **coherent but frequently *wrong* prose** when answering
  from memory.
- **Takeaway:** a tiny fine-tune neither *grounds* answers in the user's real data nor
  *reliably formats* them. Reliable running analytics need (a) real data in context and
  (b) structured, validated output — not ungrounded model recall.

## How findings bridge to the app

| Pipeline finding | App design decision | Where |
|---|---|---|
| Ungrounded model recall is wrong / loops | Never ask the model to compute or remember stats — Swift does it | `DataRetriever` |
| Base model gives coherent-but-wrong prose | Explicit **insight-first** system prompt with MUST / do-NOT rules | `SystemPromptBuilder.swift` |
| 74 examples can't teach formatting | Use `@Generable` typed output + Swift formatters; model only fills values | `ResponseTypes.swift`, `ChatViewModel.format*` |
| Model shouldn't pick tools/intents (Tool-protocol failures + fine-tune unreliability) | Swift `classify()` maps text → `Intent` enum *before* any model call | `DataRetriever.classify()` |
| GPX per-km splits are the valuable signal | Ported `parse_gpx` split logic to Swift via `HKWorkoutRoute` | `HealthKitRouteFetcher.computeKmSplits` |
| Totals / trends need precomputation | Inject precomputed totals, weekly/monthly trends, streaks | `DataRetriever.formatStructured` |
| Testing gaps (Q5 pace-filter, Q20 multi-date recovery, Q23 splits) | Added `Intent.paceFilter` + `extractPace`, multi-date recovery, real km splits | `DataRetriever.swift`, `HealthKitRouteFetcher.swift` |

## Open gaps being closed (from `testing.md`)

- **Pace-filter (Q5):** now a structured `paceFilter(faster:)` intent — the model receives
  the threshold rather than inferring it.
- **Multi-date recovery (Q20):** the recovery fetcher was extended to cover multiple dates
  (`recentRunDates` / `formatRecoveryRange`).
- **Km splits (Q23):** `HealthKitRouteFetcher` derives real per-km splits from
  `HKWorkoutRoute` locations, replacing the previous "no split data" general answer.

## Status

- Pipeline repo archived on GitHub (`melanion-pipeline`) as reference; **not required by the app**.
- The shipped app uses **Apple's on-device Foundation Model**. The fine-tuning research is
  preserved here as the rationale for the grounding / structured-output architecture.
- See [`testing.md`](./testing.md) for the device test matrix (25 questions) and the
  2026-08-27 Xcode build verification.
