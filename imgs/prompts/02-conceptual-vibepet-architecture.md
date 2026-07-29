---
type: conceptual
palette: elegant
rendering: hand-drawn
---

# Content Context

Generation directive: MUST invoke the raster image generation tool and return one finished bitmap image. Do not answer with prose and do not create SVG, HTML, CSS, canvas, or other code-based artwork.
Use case: infographic-diagram
Asset role: GitHub README architecture illustration
Output target: imgs/vibepet-architecture.png
Section title: Architecture
Content summary: VibePet receives local events from Claude Code and Codex through a small VibePetHooks helper. The helper normalizes those events and sends newline-delimited data through a local Unix socket to VibePetApp, where the desktop pet reflects activity and surfaces actionable prompts. If the app or bridge is unavailable, the tools continue through their native flow instead of being blocked.
Keywords: local-first, agent hooks, Unix socket, event bridge, desktop pet, fail-open, macOS architecture

# Visual Design

Cover theme: Local event flow
Type: conceptual
Palette: elegant
Rendering: hand-drawn
Font: clean
Text level: title-only
Mood: balanced
Aspect ratio: 16:9
Language: English

# Text Elements

Title: Architecture
Do not add node labels, UI labels, code text, terminal commands, captions, legends, or any other visible words besides the exact title "Architecture" and the watermark "caichuanwang".

# Mood Application

Use medium contrast, normal saturation, and balanced visual weight. The diagram should feel calm, understandable, local, and technically trustworthy rather than dense, corporate, or futuristic.

# Font Application

Render the exact title "Architecture" once in clean geometric sans-serif typography. Use modern, minimal letterforms with excellent readability and correct spelling. Keep the title separate from the diagram with generous breathing room.

# Composition

Type composition:

- Conceptual architecture illustration with a clear left-to-right hierarchy and clean visual zones.
- Keep 40-50% breathing room so the flow remains legible at GitHub README width.
- Use a wide horizontal composition with one continuous visual path rather than a boxed enterprise diagram.

Visual composition:

- Left zone: two small, distinct terminal-shaped panels representing two local coding agents. Differentiate them only with simple abstract glyphs and muted accent colors; do not use real product logos or readable names.
- Center-left: a compact hook relay represented by a small plug-and-bracket device receiving both event streams.
- Center: a delicate local Unix-socket connection rendered as a continuous hand-drawn cable or loop with a tiny socket motif. It must look local and device-contained, not like a cloud or network service.
- Right zone: a simplified macOS-like app window with the same original adorable 2D desktop pet used as the emotional focal point. Include one small approval speech bubble with abstract check and cross icons only.
- Main direction: organic arrows carry events from the two terminal panels through the hook relay and local socket into the app and pet.
- Fail-open path: include a secondary thin return path that visibly continues past the bridge back toward the terminal panels when the app is unavailable. Express this as an unobstructed bypass loop with an open gate or check motif, not warning text.
- Keep the title "Architecture" in a clear upper-left reserved zone and place the main flow across the middle and lower half.

Decorative:

- Refined hand-drawn connector lines, subtle pencil hatching, restrained sparkles, tiny paw-print marks, and delicate geometric ornaments.
- Use a faint rounded ground shape to unify the flow, but do not place the whole composition inside a card.
- Avoid dense grids, literal cloud icons, server racks, realistic devices, copied UI, and realistic people.

# Color Scheme

- Warm cream and soft beige background.
- Muted teal for the primary local event path and socket connection.
- Soft coral and dusty rose to distinguish the two agent inputs and warm the pet illustration.
- Restrained gold or copper highlights for the approval and fail-open accents.
- Ensure the title and arrow hierarchy remain readable.
- Color values and color names are rendering guidance only; do not display palette names, role labels, or hex codes as visible text.

# Rendering Notes

- Hand-drawn editorial illustration with organic, slightly imperfect lines and variable stroke weight.
- Fine pencil and ink outlines, gentle marker or watercolor fills, subtle paper grain, and light hatching.
- Minimal depth with soft hand-drawn shadows; no photorealism, no 3D render, no glossy stock-art appearance.
- Keep arrows and connectors visually precise despite the organic line quality.
- Preserve a sophisticated, publication-ready finish that clearly belongs to the same visual family as the VibePet hero image.

# Type Notes

- The image must read immediately as "two local coding-agent inputs flowing safely into a desktop pet application."
- The architecture should remain understandable without labels and should not resemble a cloud topology diagram.

# Palette Notes

- Sophisticated, refined, and understated.
- Use soft transitions and a balanced composition.
- Do not overuse pink or purple; muted teal and warm cream should keep the image technically grounded.

# Watermark

Include a subtle watermark "caichuanwang" at the bottom-right. It must be correctly spelled, small, legible, and low contrast at roughly 70% visual opacity. Do not let it compete with the title or illustration.

# Hard Constraints

- Output a single 16:9 bitmap architecture illustration.
- The image must remain legible at typical GitHub README width.
- Exact visible title: Architecture
- Exact visible watermark: caichuanwang
- No other visible text.
- No realistic humans.
- No copied Claude, OpenAI, Apple, GitHub, or third-party logos.
- No product screenshot imitation.
- No cloud service imagery; the bridge must read as local-only.
- No dark cyberpunk background; preserve the elegant warm-cream hand-drawn aesthetic.
