# Changelog

All notable changes to this image are documented here. It follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the version tracks the
packaged P2Rank release.

## [Unreleased]

## [2.5.1] - 2026-08-28

### Added

- Container image packaging P2Rank 2.5.1 on Eclipse Temurin 25 (LTS), built
  from a checksum-verified release tarball in a two-stage build.
- Behavioural test suite covering prediction correctness, arbitrary `--user`,
  bind-mount ownership, offline operation and heap sizing.
- Nextflow module (`modules/p2rank/main.nf`) predicting in batches through a
  dataset file and merging the per-structure CSVs into one table, with a
  worked configuration in the README.
- CI: Dockerfile and shell linting, build and test on every push plus weekly,
  vulnerability scanning, multi-architecture publishing with SBOM and build
  provenance, and a scheduled check for new upstream P2Rank releases.

### Changed

- The heap is `-XX:MaxRAMPercentage=75.0` rather than upstream's fixed
  `-Xmx2048m`, so it follows the container's memory limit and `JAVA_OPTS`
  can override it.

[unreleased]: https://github.com/rdk/p2rank-docker/compare/v2.5.1...HEAD
[2.5.1]: https://github.com/rdk/p2rank-docker/releases/tag/v2.5.1
