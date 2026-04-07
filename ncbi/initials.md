# initials for the container to download the genomes via terminal
## should have the `wget` tool
```bash
sudo apt install wget
```

## install the `datasets` tool of the ncbi
```bash
wget https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/LATEST/linux-amd64/datasets
```
## make it executable
```bash
chmod +x datasets
```
## move into the bin directory 
```bash
sudo mv datasets /usr/local/bin/
```
