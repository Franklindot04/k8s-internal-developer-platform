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

The local image tag is `idp/supply-chain-fixture:test`. It is a mutable local convenience tag, not a deployable identity. The local image ID reported by Docker is local image identity, not a registry digest, RepoDigest, or authoritative published digest.

The fixture does not publish to a registry and intentionally contains no Stage 6C+ SBOM, vulnerability scanning, provenance, attestation, signing, admission, promotion, or automatic `PlatformService` update tooling.
