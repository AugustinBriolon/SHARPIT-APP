# 1. Record architecture decisions

Date: 2026-09-21

## Status

Accepted

## Context

We need to record the architectural decisions made on this project. Until now the native
app relied on the web repository's ADRs (`../SHARPIT/docs/adr/`), which cover the shared
domain and design system but not decisions that only concern the iPhone client.

## Decision

We will use Architecture Decision Records, as described by Michael Nygard in his article "Documenting Architecture Decisions".
Decisions that concern both platforms stay in the web repository; decisions specific to the
native client live here.

## Consequences

### Positive
- Decisions are documented and discoverable by the entire team.
- New team members can understand past choices and their rationale.

### Negative
- Writing ADRs adds a small overhead to the decision-making process.

### Neutral
- ADRs are stored in `docs/adr/` and follow the `adr-tools` naming convention.

## References
- https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions
- https://github.com/npryce/adr-tools
