#!/bin/bash
set -e

# === FCQ.md 一键发布脚本 ===
# 用法: npm run publish 或 bash scripts/publish.sh

BLOG_DIR="/Users/stephenfan/个人项目/fcq-blog"
OBSIDIAN_BLOG="/Users/stephenfan/Library/Mobile Documents/com~apple~CloudDocs/Documents/Obsidian Vault/博客发布"

cd "$BLOG_DIR"

echo ""
echo "=== FCQ.md 发布工具 ==="
echo ""

# Step 1: 同步 Markdown 文件（排除模板文件）
echo "[1/5] 同步 Obsidian 文章..."
rsync -av --delete \
  --include="*.md" \
  --include="*/" \
  --exclude="模板-*" \
  --exclude="*" \
  "$OBSIDIAN_BLOG/" "$BLOG_DIR/src/blog/"
echo ""

# Step 2: 同步图片
echo "[2/5] 同步图片..."
rsync -av \
  --include="*.png" --include="*.jpg" --include="*.jpeg" \
  --include="*.gif" --include="*.webp" --include="*.svg" \
  --include="*/" \
  --exclude="*" \
  "$OBSIDIAN_BLOG/" "$BLOG_DIR/public/images/blog/" 2>/dev/null || true
echo ""

# Step 3: 转换 Obsidian Wikilink 图片语法为标准 Markdown
echo "[3/5] 转换图片链接..."
find "$BLOG_DIR/src/blog" -name "*.md" -type f | while read -r file; do
  # 将 ![[图片.png]] 转为 ![](/images/blog/图片.png)
  if grep -q '!\[\[.*\]\]' "$file" 2>/dev/null; then
    sed -i '' 's/!\[\[\([^]]*\)\]\]/![](\/images\/blog\/\1)/g' "$file"
    echo "  转换: $(basename "$file")"
  fi
done
echo ""

# Step 4: 构建验证
echo "[4/5] 构建站点..."
npm run build
echo ""

# Step 5: Git 提交并推送
echo "[5/5] 提交并推送..."
git add -A
if git diff --staged --quiet; then
  echo "  没有新的更改需要提交"
else
  git commit -m "publish: $(date '+%Y-%m-%d %H:%M')"
  git push
  echo ""
  echo "=== 发布完成！Vercel 将自动部署 ==="
fi

echo ""
