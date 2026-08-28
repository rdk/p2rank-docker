# P2Rank in Docker

Container image for [P2Rank](https://github.com/rdk/p2rank), machine learning
based prediction of ligand binding sites from protein structure.

The JRE and the trained models are part of the image, so Docker is the only
requirement on the host.

```bash
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/data" ghcr.io/rdk/p2rank \
    prank predict -f /data/1fbl.pdb -o /data/output
```

That writes `output/1fbl.pdb_predictions.csv` next to your input file, owned by you. Each row is one predicted pocket, ranked.

## What's inside

| | |
|---|---|
| P2Rank | 2.5.1 (all bundled models: `default`, `alphafold`, conservation, rescoring) |
| Java | Eclipse Temurin 25 JRE (current LTS) |
| Base | Ubuntu 24.04 |
| Size | ~620 MB |
| Platforms | `linux/amd64`, `linux/arm64` |
| Runs as | uid 1000, non-root |

## Usage

### Predict binding sites

```bash
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/data" ghcr.io/rdk/p2rank \
    prank predict -f /data/protein.pdb -o /data/output
```

Input can be `.pdb`, `.cif`, `.bcif`, optionally `.gz` or `.zst` compressed.

Output directory contains:

| File | What it holds |
|---|---|
| `*_predictions.csv` | ranked pockets: score, probability, centre coordinates, residues |
| `*_residues.csv` | per-residue scores |
| `visualizations/` | PyMOL session and scripts |
| `params.txt`, `run.log` | exactly what was run |

### Predicted structures (AlphaFold)

Structures from AlphaFold need the model trained for them, which reads the pLDDT scores:

```bash
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/data" ghcr.io/rdk/p2rank \
    prank predict -c alphafold -f /data/AF-P00520-F1.pdb -o /data/output
```

### Many structures at once

Put one path per line in a dataset file and pass it as the command's argument:

```bash
printf '/data/a.pdb\n/data/b.pdb\n' > structures.ds
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/data" ghcr.io/rdk/p2rank \
    prank predict /data/structures.ds -o /data/output -threads 8
```

### Memory

The heap follows the container's memory limit (75% of it), so give the container more and P2Rank uses more:

```bash
docker run --rm -m 16g ... # heap grows to 12 GB
```

To pin it exactly, set `JAVA_OPTS`:

```bash
docker run --rm -e JAVA_OPTS="-Xmx8g" ...
```

### Nextflow

The image carries no `ENTRYPOINT`, so it drops into a pipeline unchanged. The
minimal case is one structure per task:

```groovy
process predict_pockets {
    container 'ghcr.io/rdk/p2rank:2.5.1'

    input:  path structure
    output: path "output/*_predictions.csv"

    script:
    """
    prank predict -f ${structure} -o output
    """
}
```

#### A batching module

One task per structure pays the JVM startup cost every time. Because `prank`
takes a dataset file, a batch of structures can share a single JVM: collate the
channel, write the paths to a `.ds`, and let P2Rank thread across them.

This repo ships such a module as
[`modules/p2rank/main.nf`](modules/p2rank/main.nf). It predicts in batches and
merges the per-structure CSVs into one table with a `structure` column, since
P2Rank records the structure name only in the output filename. Copy it into
your pipeline, or include it directly:

```groovy
include { P2RANK } from './modules/p2rank/main.nf'

workflow {
    // e.g. --structures 'data/*.cif'
    P2RANK(Channel.fromPath(params.structures, checkIfExists: true))
}
```

It needs a container and two params:

```groovy
// nextflow.config

params {
    p2rank_config     = 'default'  // 'alphafold' for predicted structures
    p2rank_batch_size = 100        // structures per call; caps the blast
                                   // radius of one bad structure
}

process {
    withLabel: p2rank {
        container = 'ghcr.io/rdk/p2rank:2.5.1'
        cpus      = 4
        memory    = '8.GB'
    }
}

docker.enabled = true
```

The result is one `pockets.csv` for the run.

A few things worth knowing when wiring this up:

- **`task.cpus` and `task.memory` both do what you would expect.** `-threads`
  takes the former; the heap follows the container limit Nextflow sets from the
  latter, so no `JAVA_OPTS` is needed.
- **No model volume, no network.** The trained models are inside the image, so
  unlike tools that pull weights at runtime this needs no `containerOptions` and
  runs on air-gapped nodes.
- **The image has a JRE, not Python.** Post-processing inside these tasks has to
  be shell, awk or Java, or run in another container.
- **Batch size bounds the damage.** A structure P2Rank rejects fails its whole
  batch, so smaller batches lose less work; `errorStrategy 'ignore'` keeps one
  bad batch from killing the run.
- **Pick the model per input.** Predicted structures want `-c alphafold`, which
  reads pLDDT from the B-factor column. Split the channel by provenance if a run
  mixes experimental and predicted structures.

### Singularity / Apptainer on HPC

```bash
apptainer exec docker://ghcr.io/rdk/p2rank:2.5.1 \
    prank predict -f protein.pdb -o output
```

The image needs no network at runtime. Predictions on an air-gapped node are byte-identical to online ones, and the test suite checks that.

## Tags

| Tag | Means |
|---|---|
| `2.5.1` | the packaged P2Rank release; **use this in pipelines** |
| `latest` | newest release, moves without warning |

`2.5.1` is rebuilt when the base image picks up security updates, so it moves
too: it always means P2Rank 2.5.1, not one exact build. Pin the digest where a
run has to be byte-identical:

```bash
docker run ghcr.io/rdk/p2rank@sha256:<digest> ...
```

## Building it yourself

```bash
make build          # or: docker build -t p2rank:local .
make test           # build, then run the behavioural test suite
make lint           # hadolint + shellcheck
```

Build arguments:

| Argument | Default | Purpose |
|---|---|---|
| `P2RANK_VERSION` | `2.5.1` | which release to package |
| `P2RANK_SHA256` | *(checksum of the above)* | verifies the download; change it with the version |
| `JAVA_IMAGE` | `eclipse-temurin:25-jre-noble` | the JRE to run on |
| `P2RANK_HEAP` | `-XX:MaxRAMPercentage=75.0` | default heap policy |

The build downloads P2Rank from its GitHub release and verifies the SHA-256 before unpacking. The build context is empty by design, so nothing from your working directory ends up in the image.

## Tests

`tests/run-tests.sh` exercises the built image the way users and workflow engines actually invoke it, rather than only checking that the binary exists:

- predicts real pockets on bundled structures, with a sanity check on the top score
- runs as root, as uid 1000, and as an arbitrary uid a scheduler might pass
- writes into bind mounts with correct ownership
- produces identical results with the network disabled
- heap tracks the container limit, and `JAVA_OPTS` still overrides it

```bash
IMAGE=ghcr.io/rdk/p2rank:2.5.1 tests/run-tests.sh
```

CI runs them on every push, and weekly, so base-image drift shows up as a red build rather than a surprise.

## Design notes

**No `ENTRYPOINT`.** Nextflow and similar engines run images as `docker run <image> /bin/bash -c '...'`; an `ENTRYPOINT` would swallow that. The cost is typing `prank` in the command. For the short form: `docker run --entrypoint prank ...`.

**Non-root by default.** The image runs as uid 1000, which matches the usual single-user Linux host, so bind-mounted output is not left owned by root. Pass `-u` to override.

**Container-aware heap.** Upstream's launcher pins `-Xmx2048m` and appends it *after* `$JAVA_OPTS`, so the heap is stuck at 2 GB and callers cannot raise it. This image replaces that with `-XX:MaxRAMPercentage=75.0`: the heap now follows the container limit, and since the JVM ignores that flag when an explicit `-Xmx` is given, `JAVA_OPTS=-Xmx8g` works again.

**Checksum-pinned release.** The download is verified against a recorded SHA-256, so a rebuild either produces the same P2Rank or fails loudly.

## Troubleshooting

**`Permission denied` writing into the mounted directory.** The image runs as
uid 1000. If your host uid is different, the container cannot write your
directory. Pass your own ids, as every example above does:

```bash
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/data" ghcr.io/rdk/p2rank ...
```

**`Could not download ... ligands/download/XXX.cif`.** BioJava tries to fetch
chemical component definitions. These messages are harmless, since predictions
are identical with the network disabled, and the image pre-creates a writable
cache so they should not appear at all. Seeing them means `/tmp` is read-only
or overmounted.

**Out of memory on a large structure.** Give the container more memory
(`-m 16g`) or set the heap directly (`-e JAVA_OPTS="-Xmx12g"`).

## License and citation

This packaging is MIT licensed, as is P2Rank itself. If you use P2Rank in published work, please cite it. See [`CITATION.cff`](CITATION.cff) and the [upstream citation list](https://github.com/rdk/p2rank/blob/master/misc/citations.md).

> Krivák R, Hoksza D. *P2Rank: machine learning based tool for rapid and accurate prediction of ligand binding sites from protein structure.* Journal of Cheminformatics, 2018. [doi:10.1186/s13321-018-0285-8](https://doi.org/10.1186/s13321-018-0285-8)

For P2Rank itself (algorithm, parameters, the full user guide) see [github.com/rdk/p2rank](https://github.com/rdk/p2rank). A hosted web version is at [prankweb.cz](https://prankweb.cz).
