# Changelog

All notable changes to this image are documented here. It follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the version tracks the
packaged P2Rank release.

## [Unreleased]

### Added

- Container image packaging P2Rank 2.5.1 on Eclipse Temurin 25 (LTS), built
  from a checksum-verified release tarball in a two-stage build.
- Behavioural test suite covering prediction correctness, arbitrary `--user`,
  bind-mount ownership, offline operation and heap sizing.
- CI: Dockerfile and shell linting, build and test on every push plus weekly,
  vulnerability scanning, multi-architecture publishing with SBOM and build
  provenance, and a scheduled check for new upstream P2Rank releases.

### Changed

- The heap is `-XX:MaxRAMPercentage=75.0` rather than upstream's fixed
  `-Xmx2048m`, so it follows the container's memory limit and `JAVA_OPTS`
  can override it.
