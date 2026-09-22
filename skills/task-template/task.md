# Task N.M: [Task Name]

**Status:** Draft
**Phase:** N
**Priority:** [High | Medium | Low]
**Depends On:** [None or list of task numbers]
**Verification:** `[one runnable command that proves this task is done]`
**Created:** [Date]
**Last Updated:** [Date]

## Progress Summary

| Step | Status         | Description                  |
| ---- | -------------- | ---------------------------- |
| 1    | 🔵 NOT STARTED | [First implementation step]  |
| 2    | 🔵 NOT STARTED | [Second implementation step] |
| 3    | 🔵 NOT STARTED | [Third implementation step]  |

Derive steps from the task's acceptance criteria and key implementation work items.

## Objective

[Clear description of what this task accomplishes and why]

## Scope

### In Scope

- [Item]

### Out of Scope

- [Item]

## File Plan

```
path/to/
├── file-to-create.ext       (new)
└── file-to-modify.ext       (modify)
```

## Implementation Notes

- [Design decisions, patterns to follow]
- [References to relevant PRD or spec sections]
- [Anything non-obvious that future-you would want to know]

## Assumptions

Defaults chosen where the input was silent, so a guess is visible rather than absorbed. One line
each, with what it would take to overturn it. Delete the section if nothing was assumed.

- **[What was assumed]** - [why this default, and what would change it] (affects [criterion ID])

## Acceptance Criteria

Where the behaviour is observable, phrase it Given/When/Then with real values, so that two people
would agree on whether it is met. Number each one `AC1`, `AC2`, so a finding elsewhere can point
at it. Where a criterion fulfils one of the parent spec's success criteria, say which:

- [ ] **AC1:** Given [starting state], when [the action], then [the observable result, with values] (covers SC-01)
- [ ] **AC2:** [Concrete deliverable 2]
- [ ] **AC3:** [Concrete deliverable 3]

## Testing Strategy

- **Unit:** [specific test names and what they verify]
- **Integration:** [scenarios to cover]
- **Manual:** [edge cases to verify by hand]

## Progress Notes

### Deviations

Departures from the File Plan, one line per path, recorded when they happen. Omit the heading if
there were none.

- `path/as/planned` -> `path/as/built`, [why it moved]
- `path/dropped` dropped: [why it was not needed after all]

### [Date] - Task Created

- Drafted from spec: `[spec filename]`
- Depends on: [list completed prerequisites]
