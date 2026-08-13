# Supply-Chain Fixture

This is a test-only representative service for Stage 6B supply-chain build proof. It is not a production service, a platform API contract, or a required application language for the platform.

Go is only the fixture implementation detail. The platform remains language-neutral and continues to consume OCI image identity through the Stage 5 `PlatformService` contract.

Docker is the canonical dynamic prerequisite for this fixture. A local Go toolchain is not required.

## Commands

Run source tests in the pinned builder image:

```sh
make supply-chain-fixture-test
```

Build the local fixture image:

```sh
make supply-chain-fixture-image-build
```

Run the local runtime smoke proof:

```sh
make supply-chain-fixture-smoke-test
```

Run the dynamic aggregate:

```sh
make supply-chain-fixture-validate
```

Stage 6C1 reuses this fixture as the representative build subject for local evidence tooling. That evidence path builds one Docker image archive, loads that exact archive for smoke proof, runs one Syft cataloging operation that emits CycloneDX JSON for portable review and Syft JSON for rich scanner-native inventory evidence, scans the exact Docker archive with Grype, and validates the evidence manifest:

```sh
make supply-chain-evidence
```

The local image tag is `idp/supply-chain-fixture:test`. It is a mutable local convenience tag, not a deployable identity. The local image ID reported by Docker is local image identity, not a registry digest, RepoDigest, or authoritative published digest.

The Stage 6C1 archive SHA-256 is local verification identity for the exact archive bytes generated in that run. It is not a registry digest, published digest, Stage 5 deployable digest, or authoritative registry identity.

The fixture does not publish to a registry and intentionally contains no PR workflow, provenance, attestation, signing, admission, promotion, or automatic `PlatformService` update tooling.
