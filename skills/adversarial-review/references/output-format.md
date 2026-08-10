## Output Format

End each round with a summary block in the conversation (not in the doc):

```
## Adversarial Review — Round N

**Doc:** <path>  (v<N-1> → v<N>)

**Findings resolved this round:** <count>
- CRITICAL: <count>
- HIGH: <count>
- MEDIUM: <count>
- LOW: <count>

**Findings applied as edits:**
1. [HIGH] Section §3.2 referenced `useCanvasStore.activeDraftKey` —
   verified in src/stores/canvasStore.ts:142. ✓ kept claim, no change.
2. [CRITICAL] Section §4.1 said `reviewRepository.save()`; actual API is
   `reviewRepository.upsert(db, params)` (src/db/repositories/review.repository.ts).
   → Patched §4.1 + §4.3 + AC list.
   ...

**Open Questions added to doc:**
- §5.4: Locale fallback behaviour for `ja` is unspecified — needs PM call.

**Next round:** recommended / not needed. Reasoning: ...
```

The user reads this summary to decide whether to continue.

