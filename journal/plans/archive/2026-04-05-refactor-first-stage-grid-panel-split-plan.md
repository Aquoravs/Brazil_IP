---
title: "refactor: Split first-stage F-stat grids by panel"
type: refactor
status: completed
date: 2026-04-05
origin: user discussion on first-stage Beamer layout
---

# Split first-stage F-stat grids by panel

## Overview

The four summary grid slides in `paper/sections/first_stage.tex` currently stack Panel A (2002-fixed baseline) and Panel B (cycle-specific baseline) in a single Beamer frame. In the rendered PDF, the table body is clipped and the explanatory note falls off the frame. The layout should preserve the full numeric table because this deck is an internal research document, not a talk.

## Decision

Split each overloaded grid into two frames:

- `Panel A: 2002-fixed baseline`
- `Panel B: Cycle-specific baseline`

This keeps the full table visible while preserving the existing comparison logic and green pass/fail shading.

## Implementation Plan

1. Edit `paper/sections/first_stage.tex` so each of the four summary outcomes becomes two frames, one per panel.
2. Keep the same table columns and highlighting, but move the panel label into the frame title.
3. Retain the explanatory note under every frame so it is visible in the rendered PDF.
4. Compile `paper/sections/first_stage.tex` and visually verify the affected slides in the generated PDF.

## Acceptance Criteria

- All rows and columns of each summary grid are visible in the PDF.
- The note under each grid is visible on every frame.
- The resulting slides remain readable without shrinking the table further.

## Verification

- Compiled `paper/sections/first_stage.tex` successfully with `pdflatex -interaction=nonstopmode first_stage.tex`.
- Rendered pages 2--9 of `paper/sections/first_stage.pdf` to PNG and visually confirmed that all summary grids now fit on the slide and all notes are visible.
