# End-to-end read of the generated brief (mode=no-mistakes, target fc4365d)

Source artifact: `generated-brief-no-mistakes-after.md` (produced by
`FM_HOME=<tmp> bin/fm-brief.sh demo-ship acme-api --mode no-mistakes`).
Every `stop` / `done:` directive in that whole brief, in order:

| line | directive | kind |
|------|-----------|------|
| 8  | stop and regenerate the brief with `--herdr-lab` before dispatch | pre-dispatch safety gate |
| 16 | `blocked: launched in primary checkout...` and stop | isolation safety stop |
| 33 | "A mid-task `working:` line ... is nonterminal: do not end the turn after it; continue the same stage until a defined `done:` gate under Definition of done." | status protocol |
| 38 | same obstacle twice -> `blocked: {why}` and stop | escalation (rule 5) |
| 40 | decision above the worker -> `needs-decision: {...}` and stop | escalation (rule 6), PRESERVED |
| 45 | daemon error -> `blocked:` and stop | escalation (rule 7) |
| 56 | "The task is complete only after no-mistakes reports CI green and you can report `done: PR {url} checks green`." | the single completion bar |
| 57 | "Once the implementation is committed on your branch, proceed directly into no-mistakes validation without stopping or waiting for a firstmate steer." | commit -> validation continuation |
| 66 | "ask-user findings are never yours to answer: escalate to firstmate (rule 6) and stop." | escalation, PRESERVED |
| 71 | "After no-mistakes reports CI green ... append `done: PR {url} checks green` and stop. You are finished." | the single terminal stop |

Result: the only non-escalation stop in the document is the terminal one at line 71,
and it names the same event as the completion bar at line 56. Rule 4 (line 33) sends the
worker from any mid-task `working:` line to "a defined `done:` gate under Definition of
done", and the DOD now defines exactly one such gate. The implementation commit is a
waypoint (line 57), never a completion. Nothing in the document asks the worker to wait
for a firstmate steer, and nothing steers no-mistakes automatically on firstmate's behalf.

Before the fix the same document said, three lines apart: "The task is complete only when
committed on your branch." / "When you believe it is complete, append `done: {summary}` ...
and stop." / "Firstmate will then instruct you to run /no-mistakes" -- and then, at the end,
"After /no-mistakes reports CI green ... append `done: PR {url} checks green` and stop. You
are finished." Two completion bars, two `done:` payloads, two stops. See
`generated-brief-dod-before-after.diff`.

## AGENTS.md section 7 reconciliation
`AGENTS.md` -> 7. Task lifecycle -> Validate now reads: "the same worker proceeds directly
from its implementation commit into validation, invoking the no-mistakes skill the way its
own harness invokes skills, without waiting for a firstmate steer." That matches the
generated DOD line for line. Section 7's "PR ready" subsection already required
`done: PR <url> checks green` for no-mistakes and `done: PR <url>` for direct-PR, which is
what both DODs now state.

## Sweep result (docs + skills)
`grep` over all tracked `*.md` / `*.sh` outside `tests/` for the contradiction phrasings
("instruct you to run", "will then instruct", "complete only when committed",
"done: {summary}") returns exactly one hit: `bin/fm-brief.sh:375`, the local-only DOD,
whose terminal event genuinely IS the commit (`done: ready in branch fm/<id>`). No doc
under `docs/` and no skill under `.agents/skills/` carries the worker-stops-at-commit
handoff. `.agents/skills/harness-adapters/SKILL.md` mentions `/no-mistakes` only as
per-harness invocation forms for a skill firstmate sends into a pane, which is exactly the
ownership the AGENTS.md edit narrows it to.
