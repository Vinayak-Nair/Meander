# Meander cleanup eval

_Generated 2026-07-24 21:22 · 26 contract cases · median of timed runs_

## Models at a glance

| Model | Contract pass | Avg | p50 | p95 | Network |
|---|---|---|---|---|---|
| Raw (no cleanup) | 12/26 (46%) | 0.00 ms | 0.00 ms | 0.00 ms | no |
| Deterministic | 17/26 (65%) | 0.42 ms | 0.40 ms | 0.51 ms | no |

## Failures by rule

| Rule | Raw (no cleanup) | Deterministic |
|---|---|---|
| remove speech fillers | ❌ 2 | ✅ |
| remove 'like' as filler | ❌ 1 | ❌ 1 |
| preserve 'like' when not filler | ✅ | ✅ |
| remove accidental repetitions | ❌ 2 | ❌ 1 |
| repair false starts | ❌ 1 | ❌ 1 |
| add punctuation | ❌ 1 | ❌ 1 |
| capitalize sentences | ❌ 1 | ✅ |
| capitalize proper nouns | ❌ 1 | ❌ 1 |
| make light grammatical corrections | ❌ 1 | ❌ 1 |
| normalize spacing | ❌ 1 | ✅ |
| convert spoken punctuation | ❌ 3 | ❌ 3 |
| preserve the user's tone and vocabulary | ✅ | ✅ |
| must not summarize | ✅ | ✅ |
| must not add new information | ✅ | ✅ |
| must not make the writing more formal | ✅ | ✅ |
| must not replace simple words with sophisticated ones | ✅ | ✅ |
| must not change the user's opinion | ✅ | ✅ |
| must not remove uncertainty or hedging | ✅ | ✅ |
| must not change numbers, dates or names | ✅ | ✅ |
| must not turn short messages into essays | ✅ | ✅ |
| must not restructure entire paragraphs | ✅ | ✅ |
| must not censor informal language or profanity | ✅ | ✅ |

## Per-case detail

### removes-um-uh — _remove speech fillers_

> **In:** um so I uh went to the store

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | um so I uh went to the store | ❌ still contains "um"; still contains "uh" | 0.00 ms |
| Deterministic | So I went to the store | ✅ pass | 0.67 ms |

### removes-you-know — _remove speech fillers_

> **In:** this is you know pretty solid work

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | this is you know pretty solid work | ❌ still contains "you know" | 0.00 ms |
| Deterministic | This is pretty solid work | ✅ pass | 0.52 ms |

### removes-filler-like — _remove 'like' as filler_

> **In:** it was like really far from the station

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | it was like really far from the station | ❌ still contains "like" | 0.00 ms |
| Deterministic | It was like really far from the station | ❌ still contains "like" | 0.49 ms |

### keeps-real-like — _preserve 'like' when not filler_

> **In:** I really like this song

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | I really like this song | ✅ pass | 0.00 ms |
| Deterministic | I really like this song | ✅ pass | 0.47 ms |

### removes-doubled-word — _remove accidental repetitions_

> **In:** send the the document

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | send the the document | ❌ still contains "the the" | 0.00 ms |
| Deterministic | Send the document | ✅ pass | 0.43 ms |

### removes-repeated-phrase — _remove accidental repetitions_

> **In:** I think I think we should go

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | I think I think we should go | ❌ still contains "I think I think" | 0.00 ms |
| Deterministic | I think I think we should go | ❌ still contains "I think I think" | 0.44 ms |

### repairs-false-start — _repair false starts_

> **In:** Can you, actually, could you send it tomorrow?

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | Can you, actually, could you send it tomorrow? | ❌ still contains "can you, actually" | 0.00 ms |
| Deterministic | Can you, actually, could you send it tomorrow? | ❌ still contains "can you, actually" | 0.44 ms |

### adds-punctuation — _add punctuation_

> **In:** hello how are you doing today

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | hello how are you doing today | ❌ does not end in sentence punctuation | 0.00 ms |
| Deterministic | Hello how are you doing today | ❌ does not end in sentence punctuation | 0.43 ms |

### capitalizes-sentences — _capitalize sentences_

> **In:** hello there. how are you

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | hello there. how are you | ❌ dropped "How" | 0.00 ms |
| Deterministic | Hello there. How are you | ✅ pass | 0.43 ms |

### capitalizes-proper-nouns — _capitalize proper nouns_

> **In:** i talked to sarah about the london trip

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | i talked to sarah about the london trip | ❌ dropped "Sarah"; dropped "London" | 0.00 ms |
| Deterministic | I talked to sarah about the london trip | ❌ dropped "Sarah"; dropped "London" | 0.44 ms |

### light-grammar — _make light grammatical corrections_

> **In:** he go to the office every day

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | he go to the office every day | ❌ dropped "goes" | 0.00 ms |
| Deterministic | He go to the office every day | ❌ dropped "goes" | 0.40 ms |

### normalizes-spacing — _normalize spacing_

> **In:** hello    world   there

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | hello    world   there | ❌ still contains "  " | 0.00 ms |
| Deterministic | Hello world there | ✅ pass | 0.39 ms |

### spoken-comma — _convert spoken punctuation_

> **In:** wait comma what did you say

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | wait comma what did you say | ❌ still contains "comma"; dropped "," | 0.00 ms |
| Deterministic | Wait comma what did you say | ❌ still contains "comma"; dropped "," | 0.48 ms |

### spoken-full-stop — _convert spoken punctuation_

> **In:** that is all full stop

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | that is all full stop | ❌ still contains "full stop"; dropped "." | 0.00 ms |
| Deterministic | That is all full stop | ❌ still contains "full stop"; dropped "." | 0.41 ms |

### spoken-new-paragraph — _convert spoken punctuation_

> **In:** first idea new paragraph second idea

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | first idea new paragraph second idea | ❌ still contains "new paragraph"; missing paragraph break | 0.00 ms |
| Deterministic | First idea new paragraph second idea | ❌ still contains "new paragraph"; missing paragraph break | 0.39 ms |

### preserves-tone — _preserve the user's tone and vocabulary_

> **In:** yeah that's gonna be super cool

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | yeah that's gonna be super cool | ✅ pass | 0.00 ms |
| Deterministic | Yeah that's gonna be super cool | ✅ pass | 0.38 ms |

### no-summarize — _must not summarize_

> **In:** we should ship the feature next week but I am worried about the tests and we still need to tell the customer

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | we should ship the feature next week but I am worried about the tests and we still need to tell the customer | ✅ pass | 0.00 ms |
| Deterministic | We should ship the feature next week but I am worried about the tests and we still need to tell the customer | ✅ pass | 0.42 ms |

### no-add-info — _must not add new information_

> **In:** send the report to the team

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | send the report to the team | ✅ pass | 0.00 ms |
| Deterministic | Send the report to the team | ✅ pass | 0.37 ms |

### no-formalize — _must not make the writing more formal_

> **In:** I wanna grab lunch soon

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | I wanna grab lunch soon | ✅ pass | 0.00 ms |
| Deterministic | I wanna grab lunch soon | ✅ pass | 0.37 ms |

### no-elevate-vocab — _must not replace simple words with sophisticated ones_

> **In:** the food was good

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | the food was good | ✅ pass | 0.00 ms |
| Deterministic | The food was good | ✅ pass | 0.37 ms |

### no-change-opinion — _must not change the user's opinion_

> **In:** I think the new design is bad

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | I think the new design is bad | ✅ pass | 0.00 ms |
| Deterministic | I think the new design is bad | ✅ pass | 0.37 ms |

### keeps-hedging — _must not remove uncertainty or hedging_

> **In:** I think maybe we should wait a bit

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | I think maybe we should wait a bit | ✅ pass | 0.00 ms |
| Deterministic | I think maybe we should wait a bit | ✅ pass | 0.38 ms |

### keeps-numbers-dates-names — _must not change numbers, dates or names_

> **In:** meet Raj at 3 pm on the 5th

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | meet Raj at 3 pm on the 5th | ✅ pass | 0.00 ms |
| Deterministic | Meet Raj at 3 pm on the 5th | ✅ pass | 0.38 ms |

### no-essay — _must not turn short messages into essays_

> **In:** ok sounds good

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | ok sounds good | ✅ pass | 0.00 ms |
| Deterministic | Ok sounds good | ✅ pass | 0.36 ms |

### no-restructure — _must not restructure entire paragraphs_

> **In:** the build is broken. I will fix it after lunch

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | the build is broken. I will fix it after lunch | ✅ pass | 0.00 ms |
| Deterministic | The build is broken. I will fix it after lunch | ✅ pass | 0.37 ms |

### no-censor-profanity — _must not censor informal language or profanity_

> **In:** this is fucking brilliant work

| Model | Output | Verdict | Latency |
|---|---|---|---|
| Raw (no cleanup) | this is fucking brilliant work | ✅ pass | 0.00 ms |
| Deterministic | This is fucking brilliant work | ✅ pass | 0.39 ms |

