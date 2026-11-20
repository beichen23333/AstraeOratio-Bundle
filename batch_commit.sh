#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")" || exit 1
BATCH_SIZE=300
PENDING=".batch_commit_pending"
BRANCH=$(git branch --show-current)
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then echo "错误：当前目录不是Git仓库"; exit 1; fi
if ! git diff --cached --quiet; then echo "错误：暂存区不为空，请先检查 git status"; exit 1; fi

# 推送上一批并在成功后删除源文件（断点恢复）
finish_pending(){
    [ -f "$PENDING" ] || return 0
    echo "恢复上一批任务..."
    git push -u origin "$BRANCH"
    while IFS= read -r -d '' f; do
        if [ -f "$f" ]; then rm -f -- "$f" && echo "已删除: $f"; fi
    done < "$PENDING"
    rm -f "$PENDING"
    echo "上一批推送成功，源文件已清理"
}

finish_pending

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

while true; do
    mapfile -d '' FILES < <(git ls-files --others --exclude-standard -z)
    TOTAL=${#FILES[@]}
    [ "$TOTAL" -eq 0 ] && break
    COUNT=$((TOTAL < BATCH_SIZE ? TOTAL : BATCH_SIZE))
    printf '%s\0' "${FILES[@]:0:COUNT}" > "$PENDING"
    echo "准备处理 $COUNT 个文件（剩余未跟踪: $TOTAL）"
    git add -f --pathspec-from-file="$PENDING" --pathspec-file-nul
    if git diff --cached --quiet; then
        echo "当前批次没有可提交变更，跳过"
        rm -f "$PENDING"
        continue
    fi
    git commit -m "Batch upload $(date '+%Y%m%d_%H%M%S') ($COUNT files)"
    echo "Commit 成功，立即 Push..."
    git push origin main --force
    echo "Push 成功，开始删除本批本地文件..."
    while IFS= read -r -d '' f; do
        [ ! -f "$f" ] || rm -f -- "$f"
    done < "$PENDING"
    rm -f "$PENDING"
    echo "本批完成：已提交、已推送、已清理 $COUNT 个文件"
    echo "----------------------------------------"
done

echo "========================================"
echo "所有文件处理完成！"
echo "========================================"
