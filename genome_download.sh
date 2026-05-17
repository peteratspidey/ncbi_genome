#!/bin/bash

# ==========================================
# NCBI Complete Genome Downloader Script
# ==========================================

echo "======================================"
echo " NCBI Complete Genome Downloader"
echo "======================================"

# Check if datasets is installed
if ! command -v datasets &> /dev/null
then
    echo ""
    echo "NCBI datasets CLI not found."
    echo "Installing NCBI datasets CLI..."
    echo ""

    # Create temporary directory
    mkdir -p ~/ncbi_datasets_install
    cd ~/ncbi_datasets_install || exit

    # Download latest datasets CLI
    curl -LO https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/LATEST/linux-amd64/datasets

    # Make executable
    chmod +x datasets

    # Move to local bin
    mkdir -p ~/.local/bin
    mv datasets ~/.local/bin/

    # Add to PATH if not already added
    if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
        export PATH="$HOME/.local/bin:$PATH"
    fi

    echo ""
    echo "NCBI datasets CLI installed successfully."
    echo ""
fi

# Ask user for organism name
echo ""
read -p "Enter organism name (example: Acinetobacter baumannii): " organism

# Replace spaces with underscore for folder names
folder_name=$(echo "$organism" | tr ' ' '_')

# Create output directory
mkdir -p "$folder_name"
cd "$folder_name" || exit

echo ""
echo "Downloading COMPLETE genomes for:"
echo "$organism"
echo ""

# Download complete genomes
datasets download genome taxon "$organism" \
    --assembly-level complete \
    --exclude-atypical \
    --filename complete_genomes.zip

# Check if download succeeded
if [ $? -eq 0 ]; then
    echo ""
    echo "Download completed successfully."
    echo ""

    echo "Extracting files..."
    unzip complete_genomes.zip

    echo ""
    echo "Genome download and extraction finished."
    echo ""

    echo "Downloaded files are in:"
    pwd

else
    echo ""
    echo "Download failed."
fi
