# ADR 0001 — Liquid Glass approximation & deterministic time engine

Status: Accepted · Date: 2026-06-16

## Context

Two cross-cutting decisions shape most of the codebase and are non-obvious enough to record per
the plan's §12.14.

## Decision 1 — Approximate Liquid Glass with Haze + AGSL, split by role

There is no native Android equivalent of iOS 26's `glassEffect`. We approximate it with
[Haze](https://github.com/chrisbanes/haze) for hardware-accelerated backdrop blur + tint, plus an
optional AGSL `RuntimeShader` (API 33+) for lens refraction and a specular edge
(`core/designsystem/LiquidGlass.kt`).

The role split is mandatory and enforced by convention: **Material 3 Expressive owns content and
structure; Liquid Glass is used only for the navigation/control layer** (the floating bar,
toolbars, the scrubber card). Glass never goes on content, and glass never stacks on glass.

Accessibility and user control are first-class: the glass modifier falls back to an opaque Material
surface when the system requests reduced transparency, when the user disables the glass compositor,
or when the user forces reduced transparency (provided via `LocalGlassEnabled` /
`LocalReduceTransparencyOverride`).

## Decision 2 — Deterministic, `Clock`-injected time; the LLM never computes time

All time and solar math lives in `core/time` and is a pure function of an injected
`kotlinx.datetime.Clock` and explicit instants — never `Instant.now()` in domain code (§12.7).
This covers the shared `scrubInstant` (`TimeEngine`), the fairness ranker (`FindOverlapUseCase`),
the solar terminator and sun times (`SolarMath`), and ICS generation (`IcsGenerator`).

Consequences:

- Every zone view, the comparison strip, and the day/night map read one `scrubInstant`, so they
  always agree.
- Time logic is trivially unit-testable with a fixed clock (see `app/src/test`).
- The AI layer only proposes structured intent; the deterministic engine does all the math, and
  events are written only after an explicit user action. Zone-aware `DTSTART;TZID=…` keeps invites
  correct across zones.
