import type { CollectionEntry } from 'astro:content';

export function getVisibleBlogPosts(posts: CollectionEntry<'blog'>[]) {
	return posts
		.filter((post) => import.meta.env.DEV || !post.data.draft)
		.sort((a, b) => b.data.pubDate.valueOf() - a.data.pubDate.valueOf());
}
