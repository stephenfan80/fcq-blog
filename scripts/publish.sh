#!/bin/bash
set -e

# === FCQ.md 一键发布脚本 ===
#
# 用法 1: publish-blog                     发布"博客发布"文件夹中所有文章
# 用法 2: publish-blog "文章名.md"          发布 Obsidian 中指定的文章（自动查找图片）
# 用法 3: publish-blog "/完整路径/文章.md"  发布指定路径的文章
#
# 在任意终端位置都可运行。

BLOG_DIR="/Users/stephenfan/个人项目/fcq-blog"
VAULT="/Users/stephenfan/Library/Mobile Documents/com~apple~CloudDocs/Documents/Obsidian Vault"
OBSIDIAN_BLOG="$VAULT/博客发布"
BLOG_CONTENT="$BLOG_DIR/src/blog"
BLOG_IMAGES="$BLOG_DIR/public/images/blog"

cd "$BLOG_DIR"

echo ""
echo "=== FCQ.md 发布工具 ==="
echo ""

# --- 辅助函数：处理单篇文章的图片 ---
process_images() {
  local md_file="$1"
  local source_dir="$2"  # 文章所在目录

  # 提取所有 ![[xxx]] 中的图片引用
  local images
  images=$(grep -oE '!\[\[[^]]+\]\]' "$md_file" 2>/dev/null | sed 's/!\[\[//;s/\]\]//' || true)

  if [ -z "$images" ]; then
    return
  fi

  echo "  发现图片引用，正在处理..."
  mkdir -p "$BLOG_IMAGES"

  while IFS= read -r img; do
    [ -z "$img" ] && continue

    local found=false
    local img_basename
    img_basename=$(basename "$img")

    # 查找顺序：1) 相对于文章目录  2) attachments 子目录  3) vault 根目录  4) 全 vault 搜索
    local search_paths=(
      "$source_dir/$img"
      "$source_dir/attachments/$img_basename"
      "$VAULT/$img"
      "$VAULT/$img_basename"
    )

    for path in "${search_paths[@]}"; do
      if [ -f "$path" ]; then
        cp "$path" "$BLOG_IMAGES/$img_basename"
        echo "    复制图片: $img_basename"
        found=true
        break
      fi
    done

    if [ "$found" = false ]; then
      # 最后兜底：在整个 vault 中搜索
      local found_path
      found_path=$(find "$VAULT" -name "$img_basename" -type f 2>/dev/null | head -1)
      if [ -n "$found_path" ]; then
        cp "$found_path" "$BLOG_IMAGES/$img_basename"
        echo "    复制图片: $img_basename (全局搜索)"
      else
        echo "    ⚠ 未找到图片: $img"
      fi
    fi
  done <<< "$images"
}

# --- 辅助函数：转换 Wikilink 为标准 Markdown ---
convert_wikilinks() {
  local md_file="$1"
  if grep -q '!\[\[.*\]\]' "$md_file" 2>/dev/null; then
    # ![[path/to/图片.png]] → ![](/images/blog/图片.png)
    # 提取文件名部分（去掉路径前缀），加上 /images/blog/ 前缀
    perl -i -pe 's{!\[\[([^\]]+)\]\]}{
      my $ref = $1;
      my $basename = (split /\//, $ref)[-1];
      "![](/images/blog/$basename)"
    }ge' "$md_file"
    echo "    转换链接: $(basename "$md_file")"
  fi
}

# ============================================================
# 主逻辑
# ============================================================

if [ -n "$1" ]; then
  # --- 模式：发布指定文章 ---
  INPUT="$1"

  # 如果不是绝对路径，在 vault 中查找
  if [[ "$INPUT" != /* ]]; then
    FOUND=$(find "$VAULT" -name "$(basename "$INPUT")" -path "*$INPUT" -type f 2>/dev/null | head -1)
    if [ -z "$FOUND" ]; then
      FOUND=$(find "$VAULT" -name "$INPUT" -type f 2>/dev/null | head -1)
    fi
    if [ -z "$FOUND" ]; then
      echo "错误：找不到文章 \"$INPUT\""
      echo "提示：可以输入文件名或相对路径，脚本会在 Obsidian 中搜索"
      exit 1
    fi
    INPUT="$FOUND"
  fi

  if [ ! -f "$INPUT" ]; then
    echo "错误：文件不存在 \"$INPUT\""
    exit 1
  fi

  echo "发布文章: $(basename "$INPUT")"
  echo ""

  # 复制文章到博客内容目录
  mkdir -p "$BLOG_CONTENT"
  cp "$INPUT" "$BLOG_CONTENT/"
  local_file="$BLOG_CONTENT/$(basename "$INPUT")"

  # 检查是否有 frontmatter，没有则自动生成
  if ! head -1 "$local_file" | grep -q '^---'; then
    echo "  文章缺少 frontmatter，自动生成..."
    # 用文件名（去掉 .md）作为标题
    auto_title=$(basename "$INPUT" .md)
    temp_file=$(mktemp)
    cat > "$temp_file" <<FRONTMATTER
---
title: "$auto_title"
pubDate: $(date '+%Y-%m-%d')
tags: []
---

FRONTMATTER
    cat "$local_file" >> "$temp_file"
    mv "$temp_file" "$local_file"
  fi

  # 处理图片
  source_dir=$(dirname "$INPUT")
  process_images "$local_file" "$source_dir"

  # 转换 Wikilink
  convert_wikilinks "$local_file"

else
  # --- 模式：发布"博客发布"文件夹中所有新文章 ---
  echo "同步博客发布文件夹..."
  echo ""

  # 复制新文章到博客（不用 --delete，保留已有文章）
  # 排除模板文件
  find "$OBSIDIAN_BLOG" -name "*.md" -not -name "模板-*" -type f | while read -r src_file; do
    dest_file="$BLOG_CONTENT/$(basename "$src_file")"
    if [ ! -f "$dest_file" ] || [ "$src_file" -nt "$dest_file" ]; then
      cp "$src_file" "$dest_file"
      echo "  同步: $(basename "$src_file")"
    fi
  done

  # 处理每篇文章的图片和 Wikilink
  find "$BLOG_CONTENT" -name "*.md" -type f | while read -r file; do
    process_images "$file" "$OBSIDIAN_BLOG"
    convert_wikilinks "$file"
  done
fi

echo ""

# --- 构建 ---
echo "[构建] 生成站点..."
npm run build
echo ""

# --- Git 提交 ---
echo "[Git] 提交更改..."
git add -A
if git diff --staged --quiet; then
  echo "  没有新的更改需要提交"
else
  git commit -m "publish: $(date '+%Y-%m-%d %H:%M')"
  git push
fi
echo ""

# --- 部署到 Vercel ---
echo "[部署] 发布到 Vercel..."
npx vercel --prod --yes 2>&1 | tail -5
echo ""
echo "=== 发布完成！ ==="
echo ""
