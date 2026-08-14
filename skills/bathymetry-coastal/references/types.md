# Core TypeScript Types

```typescript
/** Vertical datum — critical to specify; mixing datums causes dangerous errors */
type VerticalDatum =
  | 'LAT'     // Lowest Astronomical Tide (chart datum in most countries)
  | 'MSL'     // Mean Sea Level
  | 'MLLW'    // Mean Lower Low Water (US chart datum)
  | 'AHD'     // Australian Height Datum
  | 'NAVD88'  // North American Vertical Datum 1988
  | 'EGM2008' // Earth Gravitational Model (used by GEBCO)
  | 'WGS84';  // Ellipsoidal height

/** A bathymetric grid (regular or irregular) */
interface BathymetricGrid {
  readonly name: string;
  readonly source: 'GEBCO' | 'multibeam' | 'lidar' | 'satellite_derived' | 'chart_digitised';
  readonly verticalDatum: VerticalDatum;
  readonly resolutionArcSec?: number;       // For regular grids
  readonly bounds: GeoBounds;
  readonly depthValues: Float32Array | readonly number[];  // Negative = below datum
  readonly rows: number;
  readonly cols: number;
  readonly noDataValue: number;
}

interface GeoBounds {
  readonly north: number;
  readonly south: number;
  readonly east: number;
  readonly west: number;
}

/** Depth contour line for rendering */
interface DepthContour {
  readonly depthM: number;               // Positive value representing depth below datum
  readonly coordinates: readonly [number, number][];  // [lon, lat] pairs
  readonly isClosed: boolean;
}

/** Coastal hazard zone */
interface CoastalHazardZone {
  readonly id: string;
  readonly hazardType: 'erosion' | 'inundation' | 'storm_surge' | 'tsunami' | 'cliff_collapse';
  readonly returnPeriodYears: number;
  readonly geometry: GeoJSON.Polygon | GeoJSON.MultiPolygon;
  readonly maxInundationDepthM?: number;
  readonly sourceStudy: string;
  readonly assessmentDate: string;
}

/** Surf break characterisation */
interface SurfBreak {
  readonly name: string;
  readonly location: { latitude: number; longitude: number };
  readonly breakType: 'beach' | 'reef' | 'point' | 'rivermouth';
  readonly facing: number;               // Direction break faces in °True
  readonly optimalSwellDirectionRange: [number, number];  // °True
  readonly optimalSwellPeriodRange: [number, number];     // seconds
  readonly optimalTideState: 'low' | 'mid' | 'high' | 'all';
  readonly seabedComposition: 'sand' | 'rock' | 'coral' | 'cobble';
  readonly depthAtBreakpointM: number;
}

/** Bathymetric profile (cross-section) */
interface BathymetricProfile {
  readonly startPoint: { latitude: number; longitude: number };
  readonly endPoint: { latitude: number; longitude: number };
  readonly distancesM: readonly number[];  // Distance along profile
  readonly depthsM: readonly number[];     // Depth at each point (positive down)
  readonly verticalDatum: VerticalDatum;
}
```
