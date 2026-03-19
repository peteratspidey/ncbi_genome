# download the genomes directly from the ncbi-datasets-cli 
## installation of the ncbi-datasets-cli
```bash
datasets download genome taxon "Shigella" \
--assembly-level chromosome,complete \
--assembly-source all \
--reference \
--include genome,gff3,protein \
--exclude-atypical \
--filename shigella_final.zip
```
> this is the test genomes download with the given filters that i will test further

## download the genome raw data that is going to curated via using bvbrc
```bash
datasets download genome taxon "Shigella" \
--assembly-level complete,chromosome,scaffold \
--assembly-source all \
--include genome \
--exclude-atypical \
--filename shigella_all_genomes.zip
```
