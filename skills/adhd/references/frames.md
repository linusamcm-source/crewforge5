# Frame catalog

## Frames

Pick 5 per run.

| Frame | Vantage prompt | Tags |
|---|---|---|
| **hardware engineer** | You think in latency, memory layout, and physical constraints. Re-ask this as a hardware/firmware problem. What does the bus topology, cache, timing budget tell you? | code, wild |
| **regulator** | You audit systems for compliance and failure modes. What must be provable, traceable, or refusable here? | design, general |
| **10-year-old** | You are a curious 10 year old who has never seen software. Describe naive but unencumbered approaches. Ignore convention. | general, wild |
| **competitor trying to break it** | You are a hostile competitor or attacker. Generate approaches that exploit, fail, or sabotage the obvious solution. Then invert into ideas. | code, design |
| **biology** | Transplant a mechanism from biology (immune systems, neural plasticity, cell signaling, evolution, gut flora). Force-fit it onto this engineering problem. | code, wild |
| **logistics** | Steal mechanisms from logistics: queues, batching, just-in-time, hub-and-spoke, returns, last-mile. Apply them literally. | code, design |
| **game design** | Approach this as a game designer. What are the loops, rewards, friction, save-states, speedrun tricks? Treat the user as a player. | design, general |
| **markets** | Treat the problem as a market. Buyers, sellers, market-makers. What does an auction, a futures contract, a clearing house look like here? | design, wild |
| **inversion** | Ask the OPPOSITE question. If goal is X, brainstorm how to guarantee NOT X. Then negate each answer back. | code, design, general |
| **extreme: $0 budget, 1 hour** | No money, no team, one hour. What is the crudest version that still does the load-bearing thing? | code, general |
| **extreme: infinite budget, 10 years** | Infinite compute, infinite engineers, a decade. What is the maximalist version? | design, wild |
| **remove the load-bearing assumption** | Name the thing everyone treats as fixed (framework, database, request-response model, network). Imagine it is gone. What is possible? | code, design, wild |
| **speedrunner** | You are a speedrunner. Find glitches, skips, out-of-bounds tricks, frame-perfect shortcuts. What is the abusive-but-legal path? | code, wild |
| **ant colony** | No central planner. Many dumb agents, local rules, pheromone trails. How does the problem solve itself emergently? | code, wild |
| **3am on-call** | You are the on-call engineer woken at 3am when this breaks. What design would let you not get paged? | code, design |

### Picking frames

For code-shaped problems: pick 4 frames tagged `code` or `design`, plus 1
tagged `wild`. For open product or strategy problems: a mix from all tags.
Vary the picks across sessions so the same problem produces different
candidate sets when re-run.
