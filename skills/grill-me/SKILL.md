---
name: grill-me
description: Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases.
disable-model-invocation: true
---

Interview me relentlessly about every aspect of this until we reach a shared understanding. Walk down each branch of the decision tree, resolving dependencies between decisions one by one. For each question, provide your recommended answer. Ultimately what we are trying to do is create complete clarity between us about the plan, decision, or idea.

Ask the questions one at a time via **AskUserQuestion**, waiting for feedback on each question before continuing. Asking multiple questions at once is bewildering.

If a *fact* can be found by exploring the environment (filesystem, tools, etc.) explore the repo with `use-repo-code` to find relevant information to inform your questions, and use the /graphify skill to establish the relationships. Look it up rather than asking me. The *decisions*, though, are mine — put each one to me and wait for my answer.

`use-repo-code` is hidden from the catalogue, so the `Skill` tool cannot reach it. Resolve it: `bash "${CREWFORGE_ROOT}/scripts/flow/subskill_resolve.sh" --load-mode use-repo-code` answers `MODE=agent`, so spawn it through the `Agent` tool with the type its frontmatter names. Never read its body inline — it forks to keep a whole pack out of this window, and this skill's whole point is a long interview that has room left for the answers.

Do not act on it until I confirm we have reached a shared understanding.