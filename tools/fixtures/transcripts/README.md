# Transcript fixtures

Recorded from a real session on 2026-09-16, not written by hand, because the whole point is that
the gate must read the shape the harness actually produces.

## What was measured

A subagent was dispatched to run one marked Bash command, and the transcripts were searched for it.

- **`transcript_path`** is `<project>/<session-id>.jsonl`.
- **Subagent transcripts** are `<project>/<session-id>/subagents/agent-<agent-id>.jsonl`, with a
  `.meta.json` beside each. So from `transcript_path`, strip `.jsonl` and look under
  `<that>/subagents/*.jsonl`.
- **The subagent's own `Bash` tool_use does not appear in the parent transcript.** The parent
  records the `Agent` tool_use and its `tool_result`, which carry the agent's prompt and its final
  report as text, but not the tool calls it made.

A note on how nearly this was measured wrong: the parent transcript did contain the probe string
several times, which looks like the subagent's command until you read them. They were the `Agent`
call, its result, and the grep commands run to do the searching, each of which quotes the string
being searched for. Counting occurrences would have produced the opposite conclusion.

## Consequence for the verification gate

A task verified by a subagent looks, to a gate that reads only `transcript_path`, exactly like a
task whose command never ran. The gate has to read the `subagents/` directory too.
