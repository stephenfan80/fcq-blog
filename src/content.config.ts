import { glob } from "astro/loaders";
import { defineCollection, z } from "astro:content";

const blog = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./src/blog" }),
  schema: z.object({
    title: z.string(),
    // 兼容 pubDate 和 date 两种格式
    pubDate: z.coerce.date().optional(),
    date: z.coerce.date().optional(),
    description: z.string().optional(),
    tags: z.array(z.string()).optional().default([]),
    draft: z.boolean().optional().default(false),
    // 忽略其他 frontmatter 字段（如 author, source, domain 等）
  }).passthrough().transform((data) => ({
    ...data,
    // 统一用 pubDate，优先 pubDate，其次 date，兜底今天
    pubDate: data.pubDate || data.date || new Date(),
  })),
});

export const collections = { blog };
