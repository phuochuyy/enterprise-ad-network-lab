# ADR-0001: Record architecture decisions

- Status: Accepted
- Date: 2026-11-27

## Context

This lab is built incrementally over several weeks. Decisions (why OPNsense, why this IP plan,
why Hyper-V instead of VMware) are easy to forget and hard to justify later in an interview or a review.

## Decision

Keep lightweight Architecture Decision Records in `docs/adr/`, numbered sequentially, using the
format *Context → Decision → Consequences*. An ADR is never edited after acceptance; it is
superseded by a new one.

## Consequences

- Every non-obvious choice has a written rationale linked from the PR that introduced it.
- Slight overhead per decision (~10 minutes).
