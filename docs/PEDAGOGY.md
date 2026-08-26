# 汉语谈话 pedagogy contract

汉语谈话 is implemented as a **language partner**, not a flashcard tutor. The system prompt and memory rules encode the following second-language-acquisition principles.

## 1. Meaning-focused interaction

Most model turns should be short enough that the learner produces a substantial share of the conversation. The model should continue a real topic rather than turning each utterance into a grammar lecture.

Implementation: `Backend/app/prompts.py` tells the partner to prefer natural Mandarin, keep turns compact, and end most turns with a natural opening for learner output.

## 2. Comprehensible but progressively richer input

Lexical and syntactic complexity should rise from demonstrated comprehension and production rather than a fixed HSK label.

Implementation: difficulty adaptation is an explicit instruction in the language-partner prompt; longer-term memory may retain demonstrated strengths/difficulties but not an Anki vocabulary list.

## 3. Pushed output and self-repair

When an error matters for meaning or is recurring, the preferred intervention is a clarification prompt or elicited self-repair. After repair, conversation resumes.

Implementation: prompt regression tests assert the self-repair requirement remains present.

## 4. Selective corrective feedback

The partner should not correct every comprehensible error. This protects fluency and interaction while still addressing consequential/repeated problems.

## 5. Contextual diversity

Useful language should recur naturally across different contexts rather than as repetitive drilling.

## 6. Mandarin-specific pronunciation model

When pronunciation is discussed, feedback should distinguish:

- segmentals (initials/finals)
- lexical tone identity
- tone contour and sandhi
- rhythm
- fluency
- intelligibility

The target is intelligible, flexible speech rather than accent elimination.

## 7. Memory discipline

Persistent memory may retain only information useful to future conversation continuity or language coaching: recurring topics, stable interaction preferences, demonstrated strengths, recurring linguistic difficulties, and clearly improving patterns. It should not become a general personal profile.

## 8. Token compression without destroying linguistic evidence

Exact user-role messages are excluded from Headroom compression. The ten most recent messages are protected. System instructions are also excluded. This preserves form-level evidence in learner Mandarin while reducing older model-context cost.

See `Backend/app/main.py` for the live compression policy and `Backend/tests/test_prompts.py` for boundary checks.
