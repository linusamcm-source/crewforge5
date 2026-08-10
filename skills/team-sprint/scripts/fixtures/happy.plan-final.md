# Mech Refactor Sprint

Plan-final for the mech subsystem refactor. Exercises inline + bullet forms of
`### Depends On:` and `### Touches:`.

## Story 9: Extract mech config loader

### Acceptance Criteria
- Config loads from `mech.config.yaml`
- Invalid config raises `MechConfigError`

### Definition of Done
- Tests green
- Lint clean

### Depends On: none
### Touches: src/mech/config/**

## Story 11: Refactor mech state machine

### Acceptance Criteria
- States transition per the spec table
- Illegal transitions are rejected

### Definition of Done
- Tests green

### Depends On: 9
### Touches:
- src/mech/state/**

## Story 12: Wire mech middleware

### Acceptance Criteria
- Middleware chains in declared order

### Definition of Done
- Tests green

### Depends On: 11
### Touches: src/mech/config/**, src/mech/middleware/index.ts

## Story 13: Mech telemetry hooks

### Acceptance Criteria
- Emits a span per state transition

### Depends On: 9
### Touches:
- src/mech/telemetry/**
