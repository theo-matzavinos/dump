// @ts-check

import mdx from "@astrojs/mdx";
import sitemap from "@astrojs/sitemap";
import { defineConfig } from "astro/config";
import remarkMermaid from "./src/plugins/remark-mermaid.mjs";
import rehypeScrollableTables from "./src/plugins/rehype-scrollable-tables.mjs";

// https://astro.build/config
export default defineConfig({
  site: "https://theo-matzavinos.github.io",
  base: "/dump",
  integrations: [mdx(), sitemap()],
  markdown: {
    remarkPlugins: [remarkMermaid],
    rehypePlugins: [rehypeScrollableTables],
    shikiConfig: {
      themes: {
        light: "github-light",
        dark: "github-dark-dimmed",
      },
      wrap: false,
      transformers: [
        {
          pre(node) {
            node.properties.tabIndex = 0;
            node.properties.role = "region";
            node.properties.ariaLabel = "Code example";
          },
        },
      ],
    },
  },
});
