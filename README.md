# pg-forge

A collection of [rattler-build](https://github.com/prefix-dev/rattler-build) recipes that build popular PostgreSQL
extensions as conda packages and publish them to the `pg-forge` channel on [prefix.dev](https://prefix.dev/channels/pg-forge).

Each subdirectory contains a `recipe.yaml` for a single extension. The recipes are built
against PostgreSQL 14, 15, 16, 17 and 18, on `linux-64`, `linux-aarch64`, `osx-64` and
`osx-arm64`.

## Available extensions

| Extension         | Purpose                                                  |
| ----------------- | -------------------------------------------------------- |
| `pgvector`        | Vector similarity search with HNSW and IVFFlat indexes   |
| `pg_cron`         | In-database cron scheduler                               |
| `pg_partman`      | Time and serial-based partition management               |
| `pg_timescaledb`  | Time-series storage and continuous aggregates            |
| `pg_repack`       | Online table reorganization without long locks           |
| `pg_squeeze`      | Online table compaction via logical replication          |
| `pg_ivm`          | Incremental view maintenance for materialized views      |
| `pg_net`          | Asynchronous HTTP requests from SQL                      |
| `pg_textsearch`   | Additional text search dictionaries and parsers          |
| `pgaudit`         | Session and object audit logging                         |
| `pgcrypto`        | Cryptographic primitives shipped with core PostgreSQL    |
| `pgsodium`        | libsodium-backed encryption and key management           |
| `pgtap`           | Unit testing framework for PostgreSQL                    |
| `hstore`          | Key/value store as a column type                         |
| `hypopg`          | Hypothetical indexes for query planning experiments      |
| `orafce`          | Oracle-compatible functions and types                    |
| `rum`             | RUM index access method for ranked full-text search      |
| `plpgsql_check`   | Static analysis for PL/pgSQL                             |
| `postgresql_hll`  | HyperLogLog cardinality estimation                       |
| `postgresql_topn` | Approximate top-N aggregates                             |
| `wal2json`        | Logical decoding output plugin emitting JSON             |
| `psycopg2`        | Python driver (libpq-based)                              |
| `psycopg`         | Python driver, version 3                                 |

## Installing

Add the channel to your `pixi.toml`:

```toml
[project]
channels = ["conda-forge", "https://prefix.dev/pg-forge"]
```

Then add the extensions you need:

```bash
pixi add postgresql pgvector pg_cron
```

The `postgresql` package itself comes from `conda-forge`. Each extension declares the
PostgreSQL version it was built against, so the solver picks a consistent set.

## Why conda packages

PostgreSQL extensions are notoriously awkward to install. They are tightly coupled to the
exact PostgreSQL `MAJOR` version they were compiled against, they need to land in
`pkglibdir` and `share/extension`, and they often depend on system libraries (libsodium,
OpenSSL, ICU, libxml2) that vary between distributions. The usual options are:

1. Compile from source against a system PostgreSQL. Works, but requires a build toolchain
   on every machine and pins you to whatever PostgreSQL the OS ships.
2. Use distribution packages. Limited selection, often outdated, and unavailable for
   recent PostgreSQL releases.
3. Bake everything into a container image. Fine for deployment, awkward for local
   development and CI.

Conda packages address each of these:

- **Relocatable binaries.** Conda packages install into a prefix, not into `/usr`. The
  extension is placed in the same prefix as the PostgreSQL binary it was built against,
  which is exactly where `pg_config` points. There is no `sudo`, no global state, and no
  conflict with anything the OS ships.
- **Reproducible across platforms.** The same recipe produces packages for Linux x86_64,
  Linux aarch64, macOS x86_64 and macOS arm64. The variant matrix in `variants.yaml`
  expands to all supported PostgreSQL versions automatically.
- **Proper dependency resolution.** Each extension package depends on the matching
  `postgresql` and `libpq` builds. Mixing PostgreSQL 16 with an extension built for
  PostgreSQL 17 is a solver error, not a runtime crash.
- **Per-project environments.** With pixi, each project gets its own PostgreSQL plus
  extensions, locked in `pixi.lock`. Two projects on the same machine can run different
  PostgreSQL versions with different extension sets. CI installs the same lockfile.
- **No container overhead.** The packages are plain files on disk. You can use them
  without Docker, layer them into a container if you want, or copy the prefix to another
  machine of the same platform.
- **Coexistence with conda-forge.** Compilers, system libraries, and PostgreSQL itself
  come from conda-forge. pg-forge only adds the extensions on top, which keeps the recipe
  surface small and the trust boundary clear.

## Build pipeline

The build-and-publish flow lives in `.github/workflows/build.yml`. On every push to
`main` and on pull requests, GitHub Actions runs the matrix:

```yaml
matrix:
  - { target: linux-64,       os: ubuntu-22.04 }
  - { target: linux-aarch64,  os: ubuntu-22.04-arm }
  - { target: osx-64,         os: macos-15-intel }
  - { target: osx-arm64,      os: macos-15 }
```

For each target, the job runs:

```bash
rattler-build build --recipe-dir . \
  --skip-existing=all \
  --target-platform=$TARGET \
  -m variants.yaml \
  -c conda-forge -c https://prefix.dev/pg-forge
```

`--recipe-dir .` walks every subdirectory looking for `recipe.yaml`, so adding a new
extension is just a matter of dropping a folder into the repo. `--skip-existing=all`
checks the destination channel before building and skips anything already published, so
unchanged recipes do not waste CI time.

The variant matrix is shared across all recipes in a single `variants.yaml`:

```yaml
zip_keys:
  - [postgresql, libpq]

postgresql: ["14", "15", "16", "17", "18"]
libpq:      ["14", "15", "16", "17", "18"]
```

Zipping `postgresql` and `libpq` keeps them in lockstep, so each extension is built five
times per platform, once per major PostgreSQL version, against the matching libpq.

To bump every recipe to its latest upstream release, the repo ships a small helper:

```bash
pixi run bump
```

which runs `rattler-build bump-recipe` against each recipe directory.

## Publishing with trusted publishing and Sigstore

Uploads to the `pg-forge` channel on prefix.dev use [trusted
publishing](https://prefix.dev/docs/prefix/trusted_publishing). There are no long-lived
API tokens stored in GitHub secrets. Instead, the workflow requests a short-lived OIDC
token from GitHub Actions:

```yaml
permissions:
  id-token: write
```

`rattler-build upload prefix` exchanges that OIDC token for an upload credential. The
prefix.dev side checks the token's claims (`repository`, `ref`, `workflow`) against the
trusted publisher configuration registered for the `pg-forge` channel. If the claims
match, the upload is allowed; otherwise it is rejected. A leaked token is useless because
it cannot be reused outside the originating workflow run, and revoking access is a
configuration change on prefix.dev rather than a token rotation.

As part of the same upload, every `.conda` file is signed using
[Sigstore](https://www.sigstore.dev/). The signature is produced with a short-lived
certificate issued by Sigstore's Fulcio CA, bound to the same OIDC identity that
authorized the upload, and recorded in the Rekor transparency log. The resulting
attestation answers a concrete question for anyone downloading the package: which git
commit, in which repository, built by which workflow, produced this artifact. There is no
key material to manage on the publishing side and no signing key to leak.

The relevant step in the workflow is just:

```bash
for file in output/**/*.conda; do
  rattler-build upload prefix -c pg-forge "$file"
done
```

Everything else (OIDC token exchange, Sigstore signing, Rekor entry) is handled by
`rattler-build` and the prefix.dev backend.

## Adding a new extension

1. Create a directory named after the extension.
2. Write a `recipe.yaml`. The minimum is a `source.url`, a `build.script` that runs
   `make install` into `$PREFIX`, and `host` requirements on `postgresql` and `libpq`.
3. Add a `tests` section that runs `initdb`, starts the cluster, runs `CREATE EXTENSION`,
   and exercises a couple of queries. The test runs during the build, so a broken recipe
   never gets published.
4. Open a pull request. CI builds the recipe across the full matrix without any further
   configuration.

`pgvector/recipe.yaml` is a good template to copy from.

## Repository layout

```
.
├── .github/workflows/build.yml   # Single CI workflow, builds and publishes everything
├── variants.yaml                 # PostgreSQL versions and shared variants
├── bump_recipes.sh               # Helper to run `rattler-build bump-recipe` everywhere
├── pixi.toml                     # rattler-build pinned for local builds
└── <extension>/recipe.yaml       # One recipe per extension
```

## License

Each extension carries its own upstream license, recorded in the recipe's `about.license`
field. The recipes themselves in this repository are released under the BSD-3-Clause
license.
