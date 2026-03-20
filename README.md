# Dump

Astro blog starter for markdown-first publishing with:

- content collections for posts in `src/content/blog`
- syntax-highlighted code blocks with light and dark themes
- Mermaid diagram rendering from fenced `mermaid` blocks
- responsive layout and a persistent theme toggle
- RSS and sitemap generation

## Commands

| Command | Action |
| :--- | :--- |
| `npm run dev` | Start the local Astro dev server |
| `npm run build` | Build the production site into `dist/` |
| `npm run preview` | Preview the production build locally |

## Writing posts

Create Markdown files in `src/content/blog` with frontmatter like:

```md
---
title: "A new post"
description: "Short summary for listings and metadata."
pubDate: "2026-03-20"
tags:
  - astro
  - notes
---
```

For diagrams, use a fenced block with the `mermaid` language:

````md
```mermaid
flowchart TD
    A[Write] --> B[Build]
    B --> C[Publish]
```
````

## Personalization

- Update site metadata in `src/consts.ts`
- Adjust the design in `src/styles/global.css`
- Replace `https://example.com` in `astro.config.mjs` with your real site URL before deploying
