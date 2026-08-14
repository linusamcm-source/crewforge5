# Add Surf-Seer Offline Cache

A single-story plan: no `## Story` headings, so the whole file is one implicit
node keyed by the filename stem, with `depends_on: []`.

### Acceptance Criteria
- Cache survives an app restart
- Stale entries are evicted after 24h

### Definition of Done
- Tests green
- Lint clean

### Touches: src/cache/**
