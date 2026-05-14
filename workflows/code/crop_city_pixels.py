#!/usr/bin/env python
# coding: utf-8
"""
Crop Mosaiks city parquet files to the actual city polygon shapes.

Each mosaiks_{UID}.parquet file contains pixels within a rectangular bounding box.
This script filters those pixels to keep only those falling inside the actual
city boundary defined in city_bounding_box_half_km.geojson.

Cropped files are written to city_embeddings_cropped/.
"""

import os
import glob
import re
import time

import geopandas as gpd
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
from shapely.geometry import Point


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
geojson_path = "/data-store/iplant/home/shared/esiil/Innovation_Summit_2026/Group_12/top5_by_continent.geojson"
input_dir = "/data-store/iplant/home/shared/esiil/Innovation_Summit_2026/Group_12/city_embeddings/"
output_dir = "./city_embeddings_cropped/" # Copy to shared folder later
os.makedirs(output_dir, exist_ok=True)

# ---------------------------------------------------------------------------
# Load city boundaries and reproject to lat/lon (EPSG:4326)
# ---------------------------------------------------------------------------
gdf = gpd.read_file(geojson_path)
gdf_ll = gdf.to_crs(epsg=4326)

# Build a lookup: UID -> geometry
city_geom = {row["UID"]: row.geometry for _, row in gdf_ll.iterrows()}

print(f"Loaded {len(city_geom)} city boundaries")

# ---------------------------------------------------------------------------
# Find all mosaiks parquet files
# ---------------------------------------------------------------------------
parquet_files = sorted(glob.glob(os.path.join(input_dir, "mosaiks_*.parquet")))
print(f"Found {len(parquet_files)} parquet files to process\n")


def _float32_schema(schema: pa.Schema) -> pa.Schema:
    """Return schema with X_* embedding columns coerced to float32."""
    return pa.schema([
        pa.field(f.name, pa.float32()) if f.name.startswith("X_") and pa.types.is_floating(f.type) else f
        for f in schema
    ])


def _cast_batch(batch: pa.RecordBatch, target_schema: pa.Schema) -> pa.RecordBatch:
    arrays = [
        batch.column(i).cast(target_schema.field(i).type) if batch.schema.field(i).type != target_schema.field(i).type
        else batch.column(i)
        for i in range(batch.num_columns)
    ]
    return pa.RecordBatch.from_arrays(arrays, schema=target_schema)


for parquet_path in parquet_files:
    # Extract UID from filename
    match = re.search(r"mosaiks_(\d+)\.parquet", os.path.basename(parquet_path))
    if not match:
        continue
    uid = int(match.group(1))

    if uid not in city_geom:
        print(f"UID {uid}: no matching city boundary, skipping")
        continue

    out_path = os.path.join(output_dir, f"mosaiks_{uid}.parquet")

    if os.path.exists(out_path):
        print(f"UID {uid}: already cropped, skipping")
        continue

    geom = city_geom[uid]

    print(f"[{parquet_files.index(parquet_path)+1}/{len(parquet_files)}] UID={uid}: reading...", flush=True)
    start = time.time()

    # Read only lon, lat and embedding columns to keep memory manageable
    df = pd.read_parquet(parquet_path)
    original_rows = len(df)

    # Create points and filter
    points = gpd.GeoDataFrame(
        df,
        geometry=gpd.points_from_xy(df["lon"], df["lat"]),
        crs="EPSG:4326"
    )

    # Keep only points within the city polygon
    masked = points[points.geometry.within(geom)]
    cropped_rows = len(masked)

    print(f"  -> {cropped_rows}/{original_rows} pixels kept "
          f"({100*cropped_rows/original_rows:.1f}%) in {(time.time()-start):.1f}s", flush=True)

    if cropped_rows == 0:
        print(f"  WARNING: No pixels survived the mask for UID={uid}")
        continue

    # Write cropped parquet with float32 embeddings
    cropped_df = masked.drop(columns=["geometry"]).reset_index(drop=True)
    table = pa.Table.from_pandas(cropped_df, preserve_index=False)
    target_schema = _float32_schema(table.schema)
    table = table.cast(target_schema)

    tmp_path = out_path + ".tmp"
    pq.write_table(table, tmp_path, compression="snappy")
    os.replace(tmp_path, out_path)

    print(f"  -> wrote {out_path}\n")

print("Done.")
