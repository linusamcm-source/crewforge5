# Datum & Coordinate Handling

**Critical**: bathymetric depths are meaningless without a known vertical datum.

```typescript
/**
 * Approximate datum conversions (site-specific offsets required for precision).
 * These are rough global averages — for production use, obtain local datum
 * relationships from the national hydrographic office.
 */
export function convertDatum(
  depthM: number,
  from: VerticalDatum,
  to: VerticalDatum,
  localOffset?: number
): number {
  if (from === to) return depthM;
  if (localOffset !== undefined) return depthM + localOffset;

  // Warn: this is approximate — log a warning in development
  console.warn(
    `Datum conversion ${from} → ${to} using approximate global offset. ` +
    `Obtain local offset from hydrographic office for production use.`
  );

  // Very approximate offsets relative to MSL (metres)
  const toMsl: Partial<Record<VerticalDatum, number>> = {
    MSL: 0,
    LAT: -0.5,    // LAT is typically ~0.5m below MSL (varies hugely by location)
    MLLW: -0.3,
    AHD: 0.0,     // AHD ≈ MSL around Australia
  };

  const fromOffset = toMsl[from] ?? 0;
  const toOffset = toMsl[to] ?? 0;
  return depthM + (fromOffset - toOffset);
}
```
