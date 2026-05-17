#!/bin/bash

# =====================================================================
# NCBI Genome Downloader + Metadata Extraction Pipeline
# =====================================================================
# Steps:
#   1. Check / install NCBI datasets CLI
#   2. Download complete genomes for a given organism
#   3. Extract & unzip the downloaded archive
#   4. Parse assembly_data_report.jsonl  ->  metadata.tsv
#   5. Clean year & country              ->  step2.tsv
#   6. Filter Complete Genome only       ->  final_metadata.tsv
#
# Requirements: bash, python3 (stdlib only), curl, unzip
# =====================================================================

echo "======================================================"
echo "  NCBI Genome Downloader + Metadata Extraction"
echo "======================================================"

# -------------------------------------------------------
# STEP 1 — Check / install NCBI datasets CLI
# -------------------------------------------------------
if ! command -v datasets &> /dev/null; then
    echo ""
    echo "NCBI datasets CLI not found. Installing..."
    echo ""

    mkdir -p ~/ncbi_datasets_install
    cd ~/ncbi_datasets_install || exit 1

    curl -LO https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/LATEST/linux-amd64/datasets
    chmod +x datasets
    mkdir -p ~/.local/bin
    mv datasets ~/.local/bin/

    if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
        export PATH="$HOME/.local/bin:$PATH"
    fi

    cd - || exit 1
    echo ""
    echo "NCBI datasets CLI installed successfully."
    echo ""
fi

# -------------------------------------------------------
# STEP 2 — Ask for organism name
# -------------------------------------------------------
echo ""
read -p "Enter organism name (e.g. Morganella morganii): " organism

if [ -z "$organism" ]; then
    echo "ERROR: No organism name entered. Exiting."
    exit 1
fi

folder_name=$(echo "$organism" | tr ' ' '_')
mkdir -p "$folder_name"
cd "$folder_name" || exit 1

echo ""
echo "Working directory : $(pwd)"
echo "Organism          : $organism"
echo ""

# -------------------------------------------------------
# STEP 3 — Download complete genomes
# -------------------------------------------------------
echo "------------------------------------------------------"
echo "[Step 1/5] Downloading Complete genomes from NCBI..."
echo "------------------------------------------------------"

datasets download genome taxon "$organism" \
    --assembly-level complete \
    --exclude-atypical \
    --filename complete_genomes.zip

if [ $? -ne 0 ]; then
    echo ""
    echo "ERROR: Download failed. Check organism name or internet connection."
    exit 1
fi

echo ""
echo "Download completed successfully."
echo ""

# -------------------------------------------------------
# STEP 4 — Extract the zip archive
# -------------------------------------------------------
echo "------------------------------------------------------"
echo "[Step 2/5] Extracting archive..."
echo "------------------------------------------------------"

unzip -o complete_genomes.zip

if [ $? -ne 0 ]; then
    echo "ERROR: Extraction failed."
    exit 1
fi

echo ""
echo "Extraction complete."
echo ""

JSONL_FILE=$(find . -name "assembly_data_report.jsonl" 2>/dev/null | head -1)

if [ -z "$JSONL_FILE" ]; then
    echo "ERROR: assembly_data_report.jsonl not found after extraction."
    exit 1
fi

echo "Metadata source   : $JSONL_FILE"
echo ""

# -------------------------------------------------------
# STEP 5 — Parse NCBI jsonl -> metadata.tsv
#           stdlib only: json + csv
# -------------------------------------------------------
echo "------------------------------------------------------"
echo "[Step 3/5] Parsing NCBI JSON -> metadata.tsv ..."
echo "------------------------------------------------------"

python3 << 'PYEOF'
import json, csv, os, sys

jsonl_file = None
for root, dirs, files in os.walk("."):
    for f in files:
        if f == "assembly_data_report.jsonl":
            jsonl_file = os.path.join(root, f)
            break
    if jsonl_file:
        break

if not jsonl_file:
    print("ERROR: assembly_data_report.jsonl not found.")
    sys.exit(1)

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

        genome_id   = rec.get("accession", "")
        genome_name = rec.get("assemblyInfo", {}).get("assemblyName", "")
        assembly    = genome_name

        org     = rec.get("organism", {})
        species = org.get("organismName", "")
        strain  = org.get("infraspecificNames", {}).get("strain", "")

        asm_info       = rec.get("assemblyInfo", {})
        assembly_level = asm_info.get("assemblyLevel", "")
        bioproject     = asm_info.get("bioprojectAccession", "")
        genbank_acc    = asm_info.get("biosampleAccession", "")

        biosample  = asm_info.get("biosample", {})
        attributes = {
            a["name"]: a["value"]
            for a in biosample.get("attributes", [])
            if "name" in a and "value" in a
        }

        collection_date = (
            attributes.get("collection_date") or
            biosample.get("collectionDate") or
            "unknown"
        )

        geo_loc = (
            attributes.get("geo_loc_name") or
            attributes.get("geographic location") or
            "missing"
        )

        host = (
            attributes.get("host") or
            attributes.get("Host") or
            "missing"
        )

        isolation_source = (
            attributes.get("isolation_source") or
            attributes.get("Isolation source") or
            ""
        )

        rows.append({
            "Genome_ID":         genome_id,
            "Genome_Name":       genome_name,
            "Species":           species,
            "Strain":            strain,
            "Country":           geo_loc,
            "Host":              host,
            "Year":              collection_date,
            "Isolation_Source":  isolation_source,
            "Assembly_Level":    assembly_level,
            "Genome_Quality":    "",
            "BioProject":        bioproject,
            "Assembly":          assembly,
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

print("  Done -- %d genomes written to metadata.tsv" % len(rows))
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Step 3 failed (JSON parsing)."
    exit 1
fi

# -------------------------------------------------------
# STEP 6 — Clean metadata -> step2.tsv
#           stdlib only: csv + re
#           * Year: extract 4-digit year from date string
#           * Country: strip state/region after ':'
# -------------------------------------------------------
echo ""
echo "------------------------------------------------------"
echo "[Step 4/5] Cleaning metadata -> step2.tsv ..."
echo "------------------------------------------------------"

python3 << 'PYEOF'
import csv, re

def extract_year(val):
    if not val or val.strip().lower() in ("unknown", "not provided", "missing", "na", ""):
        return ""
    match = re.search(r"\b(19|20)\d{2}\b", val)
    return match.group() if match else ""

def clean_country(val):
    if not val:
        return val
    val = val.strip()
    return val.split(":")[0].strip() if ":" in val else val

with open("metadata.tsv", newline="") as fin, \
     open("step2.tsv", "w", newline="") as fout:

    reader = csv.DictReader(fin, delimiter="\t")
    writer = csv.DictWriter(fout, fieldnames=reader.fieldnames, delimiter="\t")
    writer.writeheader()

    count = 0
    for row in reader:
        row["Year"]    = extract_year(row["Year"])
        row["Country"] = clean_country(row["Country"])
        writer.writerow(row)
        count += 1

print("  Done -- %d genomes written to step2.tsv" % count)
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Step 4 failed (cleaning)."
    exit 1
fi

# -------------------------------------------------------
# STEP 7 — Filter Complete Genome -> final_metadata.tsv
#           stdlib only: csv
# -------------------------------------------------------
echo ""
echo "------------------------------------------------------"
echo "[Step 5/5] Filtering Complete Genomes -> final_metadata.tsv ..."
echo "------------------------------------------------------"

python3 << 'PYEOF'
import csv

with open("step2.tsv", newline="") as fin, \
     open("final_metadata.tsv", "w", newline="") as fout:

    reader = csv.DictReader(fin, delimiter="\t")
    writer = csv.DictWriter(fout, fieldnames=reader.fieldnames, delimiter="\t")
    writer.writeheader()

    total, kept = 0, 0
    for row in reader:
        total += 1
        if row.get("Assembly_Level", "").strip() == "Complete Genome":
            writer.writerow(row)
            kept += 1

print("  Done -- %d Complete Genome assemblies written to final_metadata.tsv  (%d total)" % (kept, total))
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Step 5 failed (filtering)."
    exit 1
fi

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
echo ""
echo "======================================================"
echo "  Pipeline Complete"
echo "======================================================"

python3 << 'PYEOF'
import csv
from collections import Counter

def count_tsv(path):
    with open(path, newline="") as f:
        return sum(1 for _ in csv.DictReader(f, delimiter="\t"))

def assembly_counts(path):
    counts = Counter()
    with open(path, newline="") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            counts[row.get("Assembly_Level", "").strip()] += 1
    return counts

meta_n  = count_tsv("metadata.tsv")
step2_n = count_tsv("step2.tsv")
final_n = count_tsv("final_metadata.tsv")
levels  = assembly_counts("step2.tsv")

print("  metadata.tsv        : %5d genomes  (all assemblies | full date | full country)" % meta_n)
print("  step2.tsv           : %5d genomes  (all assemblies | year only | country cleaned)" % step2_n)
print("  final_metadata.tsv  : %5d genomes  (Complete Genome only)" % final_n)
print()
print("  Assembly level breakdown (step2):")
for level, count in sorted(levels.items(), key=lambda x: -x[1]):
    tag = "  <- final_metadata.tsv" if level == "Complete Genome" else ""
    print("    %-20s : %5d%s" % (level, count, tag))
PYEOF

echo ""
echo "  Output folder : $(pwd)"
echo "  Files         : metadata.tsv | step2.tsv | final_metadata.tsv"
echo "  Genome files  : ncbi_dataset/data/<accession>/*.fna"
echo "======================================================"
echo ""
