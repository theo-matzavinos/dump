// @ts-check

import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';
import { defineConfig } from 'astro/config';
import remarkMermaid from './src/plugins/remark-mermaid.mjs';

// https://astro.build/config
export default defineConfig({
	site: 'https://theo-matzavinos.github.io',
	base: '/dump',
	integrations: [mdx(), sitemap()],
	markdown: {
		remarkPlugins: [remarkMermaid],
		shikiConfig: {
			themes: {
				light: 'github-light',
				dark: 'github-dark-dimmed',
			},
			wrap: true,
		},
	},
});
