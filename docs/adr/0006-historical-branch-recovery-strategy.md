# ADR 0006: Historical Branch Recovery Strategy

## Status

Approved foundational decision.

## Context

The repository has historical branches with useful intent but incomplete or unsafe implementation. The project must preserve contributor attribution while avoiding unreviewed wholesale merges of stale work.

## Decision

Treat historical branches as design and evidence references. Do not merge them wholesale, cherry-pick them by default, rewrite them, or delete them until recovery is complete and explicitly approved. Recover useful concepts through deliberate reimplementation or tightly reviewed selective file recovery.

## Rationale

This keeps historical authorship intact while preventing incomplete scripts, broken chart templates, or inaccurate documentation from becoming authoritative project state. It also lets one maintainer complete the platform independently.

## Alternatives Considered

- Merge historical feature branches directly: preserves work quickly, but would import incomplete implementation and stale assumptions.
- Delete historical branches immediately: reduces clutter, but loses recovery evidence and contributor context.
- Cherry-pick all historical commits: preserves commit granularity, but would import low-quality or incomplete implementation along with useful ideas.

## Consequences

Future recovery work must state what is being reused, why it is safe, and how it was validated. Branch deletion remains out of scope until useful content has either been recovered or explicitly retired.

## Follow-Up Implications

The service-generator area can later become an isolated collaborator workstream. It must not block the owner from completing the platform.
