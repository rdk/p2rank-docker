# TODO

Working notes on what to do next, roughly in the order worth doing it.
Findings were verified against the repo and the GitHub API on 2026-08-28, not
inferred; the evidence is recorded with each item so a stale entry is easy to
spot.

## P0 — the image has never been published

Nothing else matters until this is done. The README opens with
`docker run ghcr.io/rdk/p2rank` and uses that image in seven examples, and the
Nextflow section tells people to pin `ghcr.io/rdk/p2rank:2.5.1`. None of it is
pullable today.

Evidence:

- `git tag` — empty. `gh release list` — empty.
- `gh api /users/rdk/packages/container/p2rank` — 404, package not found.
- Anonymous manifest fetch of `:2.5.1` and `:latest` — HTTP 403, both.

- [x] **Gate the release on the tests before tagging anything.** Done. The
      build-and-test job now lives in `.github/workflows/build-test.yml` behind
      `on: workflow_call`; `ci.yml` calls it and `release.yml` has a `test` job
      calling the same workflow with `publish` set to `needs: test`. Caveat: the
      gate is amd64 only — `load: true` cannot load a multi-platform image into
      the daemon — so arm64 is still covered only by the in-Dockerfile smoke
      prediction under emulation.

- [ ] **Tag `v2.5.1` and let `release.yml` publish.**
- [ ] **Verify the published image**, rather than trusting a green run:
      `IMAGE=ghcr.io/rdk/p2rank:2.5.1 tests/run-tests.sh` against the real
      registry copy, on both architectures if a machine is available.
- [x] **Confirm the `latest` tag actually lands.** Done — but by replacing the
      mechanism rather than checking it. The dead `enable={{is_default_branch}}`
      line is gone; `flavor: latest=false` plus one explicit `type=raw` line is
      now the only source of `latest`. The `type=semver` lines went too: only
      `2.5.1` of upstream's versions is valid semver (`2.5`, `2.6-alpha`,
      `2.1-dev.1` are not), and `procSemver` emits *no tag at all* for those.
      Image tags now come from `ARG P2RANK_VERSION`. Still verify on the first
      real release.
- [x] **Fold the CHANGELOG `[Unreleased]` section into `[2.5.1]`.** Done, dated
      2026-08-28 with an empty `[Unreleased]` kept on top and compare/release
      link definitions added. Correct the date if the tag lands on another day.

## P1 — coverage gaps

- [x] **Single-source the P2Rank version.** Done. `ARG P2RANK_VERSION` in the
      Dockerfile is now the only copy: the Makefile derives `VERSION` from it
      (and no longer passes a `--build-arg` identical to the default),
      `tests/run-tests.sh` derives `EXPECTED_VERSION` from it, and
      `release.yml` derives the image tags from it. Still worth fixing the
      "bump EXPECTED_VERSION in CI" sentence in the
      `upstream-release-check.yml` issue body, which is now doubly wrong.

- [ ] **Test the input formats the README advertises.** Every current test uses
      `.pdb`, while the README promises `.pdb`, `.cif`, `.bcif`, optionally
      `.gz`/`.zst`. mmCIF matters most: it is what the annotation pipelines
      downstream of this image actually feed in.
- [ ] **Test `-c alphafold`.** Advertised for predicted structures, reads pLDDT
      from the B-factor column, and is what a pipeline uses for AlphaFold models
      — currently unexercised.
- [ ] **Test the dataset-file (`.ds`) path.** It is the core mechanism of the
      shipped Nextflow module and the batching section of the README, and no
      test touches it.
- [ ] **Smoke-test `modules/p2rank/main.nf` in CI.** The module is offered to
      consumers and documented at length, but nothing ever runs it. A Nextflow
      run over two structures covers the module and the `.ds` batching path at
      once.
- [ ] **Consider a behavioural run on arm64.** It is published but only ever
      exercised by the in-Dockerfile smoke prediction under emulation.

## P2 — supply-chain consistency

- [ ] **Pin actions by commit digest.** They are on floating tags (`@v4`,
      `@v6`) while the P2Rank tarball gets a SHA-256 and the image gets an SBOM
      and provenance attestation. Dependabot updates digest pins fine.
- [ ] **Set `permissions: contents: read` at the top of `ci.yml`.**
      `release.yml` scopes its token; `ci.yml` runs on the default grant.

## P3 — housekeeping

- [ ] **Rebase the six open dependabot PRs (#1, #2, #3, #5, #6, #7).** Two show
      red CI — `actions/checkout` 4→7 and `setup-buildx` 3→4 — but the failures
      are not incompatibilities: both fail in the `scan` job on the bundled
      jackson-core CVE, having run at 12:14 on 2026-08-27, four minutes before
      the `.trivyignore.yaml` format fix (a6d4031) landed at 12:18. The
      metadata-action PR that ran after the fix passed. Rebasing should turn
      them green.

## Nextflow module nits

Lower value than the above, but all real:

- [ ] **Give the params in-module defaults.** A consumer who forgets
      `params.p2rank_config` or `params.p2rank_batch_size` gets a confusing null
      error rather than a sensible fallback.
- [ ] **Total failure currently looks like success.** With `errorStrategy
      'ignore'`, if every batch fails then `RUN_P2RANK.out.predictions.collect()`
      emits nothing, `MERGE_P2RANK` never runs, and the pipeline finishes with
      no `pockets.csv` and no error.
- [ ] **`out/*_residues.csv` is a required output** that nothing downstream
      consumes, so a config which does not emit residues fails the task for no
      reason.
