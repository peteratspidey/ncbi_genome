#!/bin/bash

# ==========================================
# NCBI Genome Metadata Extraction Pipeline
# ==========================================
# Generates 3 output files:
#   metadata.tsv        - All genomes, full collection date, full country
#   step2.tsv           - All genomes, year only, country cleaned (state stripped)
#   final_metadata.tsv  - Complete Genome assemblies only (filtered from step2)
# ==========================================

echo "======================================"
echo " NCBI Metadata Extraction Pipeline"
echo "======================================"

# ---- Locate the NCBI jsonl file ----
JSONL_FILE=$(find . -name "assembly_data_report.jsonl" 2>/dev/null | head -1)

if [ -z "$JSONL_FILE" ]; then
    echo ""
    echo "ERROR: assembly_data_report.jsonl not found."
    echo "Make sure you are running this script from the organism download folder"
    echo "created by genome_download.sh (e.g., Morganella_morganii/)"
    echo ""
    exit 1
fi

echo ""
echo "Found metadata file: $JSONL_FILE"
echo ""

# ==========================================
# STEP 1 — Parse NCBI jsonl -> metadata.tsv
# (all genomes, full date, full country string)
# ==========================================
echo "[Step 1] Parsing NCBI JSON → metadata.tsv ..."

python3 << 'PYEOF'
import json
import csv
import sys
import os

jsonl_file = None
for root, dirs, files in os.walk("."):
    for f in files:
        if f == "assembly_data_report.jsonl":
            jsonl_file = os.path.join(root, f)
            break
    if jsonl_file:
        break

rows = []

with open(jsonl_file, "r") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue

        # --- Core identifiers ---
        genome_id   = rec.get("accession", "")
        genome_name = rec.get("assemblyInfo", {}).get("assemblyName", "")
        assembly    = genome_name  # same value used in both columns

        # --- Organism ---
        organism    = rec.get("organism", {})
        species     = organism.get("organismName", "")
        infranames  = organism.get("infraspecificNames", {})
        strain      = infranames.get("strain", "")

        # --- Assembly info ---
        asm_info        = rec.get("assemblyInfo", {})
        assembly_level  = asm_info.get("assemblyLevel", "")
        bioproject      = asm_info.get("bioprojectAccession", "")
        genbank_acc     = asm_info.get("biosampleAccession", "")

        # --- Isolate / BioSample attributes ---
        # Try top-level isolate block first, then biosample attributes
        isolate     = rec.get("assemblyInfo", {}).get("biosample", {})
        attributes  = { a["name"]: a["value"]
                        for a in isolate.get("attributes", [])
                        if "name" in a and "value" in a }

        # Collection date (kept as full date string for metadata.tsv)
        collection_date = attributes.get("collection_date", "")
        if not collection_date:
            collection_date = isolate.get("collectionDate", "unknown")

        # Geographic location (full, may include state e.g. "USA:AL")
        geo_loc = attributes.get("geo_loc_name", "")
        if not geo_loc:
            geo_loc = attributes.get("geographic location", "")
        if not geo_loc:
            geo_loc = "missing"

        # Host
        host = attributes.get("host", "")
        if not host:
            host = attributes.get("Host", "")
        if not host:
            host = "missing"

        # Isolation source
        isolation_source = attributes.get("isolation_source", "")
        if not isolation_source:
            isolation_source = attributes.get("Isolation source", "")

        rows.append({
            "Genome_ID":        genome_id,
            "Genome_Name":      genome_name,
            "Species":          species,
            "Strain":           strain,
            "Country":          geo_loc,
            "Host":             host,
            "Year":             collection_date,
            "Isolation_Source": isolation_source,
            "Assembly_Level":   assembly_level,
            "Genome_Quality":   "",
            "BioProject":       bioproject,
            "Assembly":         assembly,
            "GenBank_Accession": genbank_acc,
        })

fieldnames = [
    "Genome_ID", "Genome_Name", "Species", "Strain",
    "Country", "Host", "Year", "Isolation_Source",
    "Assembly_Level", "Genome_Quality", "BioProject",
    "Assembly", "GenBank_Accession"
]

with open("metadata.tsv", "w", newline="") as out:
    writer = csv.DictWriter(out, fieldnames=fieldnames, delimiter="\t")
    writer.writeheader()
    writer.writerows(rows)

print(f"  metadata.tsv written — {len(rows)} genomes")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Step 1 failed."
    exit 1
fi

# ==========================================
# STEP 2 — Clean metadata -> step2.tsv
# • Extract year only from collection date
# • Strip state/region from Country (keep only country name before ':')
# ==========================================
echo "[Step 2] Cleaning metadata → step2.tsv ..."

python3 << 'PYEOF'
import pandas as pd

df = pd.read_csv("metadata.tsv", sep="\t", dtype=str)

# --- Clean Year: extract 4-digit year ---
def extract_year(val):
    if pd.isna(val) or str(val).strip().lower() in ("unknown", "not provided", "missing", ""):
        return float("nan")
    val = str(val).strip()
    # Match 4-digit year anywhere in the string
    import re
    match = re.search(r"\b(19|20)\d{2}\b", val)
    if match:
        return float(match.group())
    return float("nan")

df["Year"] = df["Year"].apply(extract_year)

# --- Clean Country: strip state/region after ':' ---
def clean_country(val):
    if pd.isna(val):
        return val
    val = str(val).strip()
    if ":" in val:
        val = val.split(":")[0].strip()
    return val

df["Country"] = df["Country"].apply(clean_country)

df.to_csv("step2.tsv", sep="\t", index=False)
print(f"  step2.tsv written — {len(df)} genomes")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Step 2 failed."
    exit 1
fi

# ==========================================
# STEP 3 — Filter Complete Genomes -> final_metadata.tsv
# ==========================================
echo "[Step 3] Filtering Complete Genomes → final_metadata.tsv ..."

python3 << 'PYEOF'
import pandas as pd

df = pd.read_csv("step2.tsv", sep="\t", dtype=str)

final = df[df["Assembly_Level"].str.strip() == "Complete Genome"].copy()
final.to_csv("final_metadata.tsv", sep="\t", index=False)

print(f"  final_metadata.tsv written — {len(final)} Complete Genome assemblies")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Step 3 failed."
    exit 1
fi

# ==========================================
# Summary
# ==========================================
echo ""
echo "======================================"
echo " Metadata Extraction Complete"
echo "======================================"

python3 << 'PYEOF'
import pandas as pd

meta  = pd.read_csv("metadata.tsv",       sep="\t")
step2 = pd.read_csv("step2.tsv",          sep="\t")
final = pd.read_csv("final_metadata.tsv", sep="\t")

print(f"  metadata.tsv        : {len(meta):>5} rows  (all assemblies, full date, full country)")
print(f"  step2.tsv           : {len(step2):>5} rows  (all assemblies, year only, country cleaned)")
print(f"  final_metadata.tsv  : {len(final):>5} rows  (Complete Genome only)")
print()
print("  Assembly level breakdown (step2):")
for level, count in step2["Assembly_Level"].value_counts().items():
    marker = " ← kept in final" if level == "Complete Genome" else ""
    print(f"    {level:<20}: {count}{marker}")
PYEOF

echo ""
echo "Output files saved in: $(pwd)"
echo ""
