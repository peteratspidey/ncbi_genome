# ncbi_genome
how to download genome from the ncbi genome database
* for the ncbi the methods is downloading from the ftp server directly from the terminal 
* `ncbi datasets CLI` - for the ncbi genome
* `p3-CLI (PATRIC CLI ) for the BVBRC genome download

## other methods that can be used to download the genomes for the species 
| Method Name                                | Purpose                                              |
| ------------------------------------------ | ---------------------------------------------------- |
| **BV-BRC Direct Filter Query (p3-genome)** | Fast, clean metadata retrieval with built-in filters |
| **Local Post-Processing Filter (awk)**     | Advanced filtering when BV-BRC fields vary           |
| **Parallel Downloader (xargs)**            | Fast multi-threaded downloads                        |
| **Bash Function-Based Download**           | Structured and reusable download logic               |
| **Automated Pipeline Script Workflow**     | Reproducible large-scale genome download             |
| **Metadata Validation / Preview**          | Confirm number of genomes, inspect sample            |
| **Boolean Normalization Method**           | Handle inconsistent true/false formats               |
| **Failure Logging and Retry**              | Robust workflow with recovery capability             |
| **Genome/Protein/CDS Retrieval Commands**  | Extract biological sequences                         |


### genome download from the BVBRC using p3 CLI method
```bash
p3-genome --eq taxon_lineage_names,Shigella \
          --eq genome_status,Complete \
          --eq quality,Good \
          --eq public,true \
          --select genome_id,genome_name \
          > shigella_bvbrc_list.tsv
```
## start with the installation
```bash
conda install -c bioconda p3-cli
```
