import { getCollection } from "astro:content";
import rss from "@astrojs/rss";
import { SITE_DESCRIPTION, SITE_TITLE } from "../consts";
import { getVisibleBlogPosts } from "../utils/blog";

export async function GET(context) {
  const posts = getVisibleBlogPosts(await getCollection("blog"));
  const basePath = `${import.meta.env.BASE_URL.replace(/\/$/, "")}/`;
  const siteRoot = new URL(basePath, context.site);

  return rss({
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
    site: siteRoot,
    items: posts.map((post) => ({
      ...post.data,
      link: `blog/${post.id}/`,
    })),
  });
}
