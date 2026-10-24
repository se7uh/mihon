#!/usr/bin/env bash
set -e

TARGET_BRANCH="${1:-data-saver}"
UPSTREAM_URL="https://github.com/mihonapp/mihon.git"

echo "=== Mihon Upstream Sync ==="
echo "Target branch: ${TARGET_BRANCH}"

# 1. Ensure upstream remote exists
if ! git remote get-url upstream >/dev/null 2>&1; then
    echo "Adding upstream remote: ${UPSTREAM_URL}"
    git remote add upstream "${UPSTREAM_URL}"
else
    echo "Upstream remote already configured."
fi

# 2. Fetch upstream main
echo "Fetching upstream main..."
git fetch upstream main

# 3. Checkout target branch
echo "Checking out ${TARGET_BRANCH}..."
git checkout "${TARGET_BRANCH}"

# 4. Attempt merge
echo "Merging upstream/main into ${TARGET_BRANCH}..."
if git merge upstream/main; then
    echo "Successfully merged upstream/main with no conflicts!"
    exit 0
fi

echo "Merge conflicts detected. Applying known automatic resolutions..."

# Auto-resolve A: Remove update_website.yml if deleted in branch
if git status --porcelain | grep -q "DU .github/workflows/update_website.yml\|UD .github/workflows/update_website.yml"; then
    echo "Removing .github/workflows/update_website.yml..."
    git rm -f .github/workflows/update_website.yml 2>/dev/null || true
fi

# Auto-resolve B: ImageUtil.kt tall image splitting removal
if git status --porcelain | grep -q "core/common/src/main/kotlin/tachiyomi/core/common/util/system/ImageUtil.kt"; then
    echo "Accepting upstream ImageUtil.kt (tall image splitting was replaced by 4MB chunk streaming)..."
    git checkout --theirs core/common/src/main/kotlin/tachiyomi/core/common/util/system/ImageUtil.kt
    git add core/common/src/main/kotlin/tachiyomi/core/common/util/system/ImageUtil.kt
fi

REMAINING_CONFLICTS=$(git status --porcelain | grep -E "^(UU|AA|DD|AU|UA|DU|UD)" | awk '{print $2}')

if [ -z "${REMAINING_CONFLICTS}" ]; then
    echo "All conflicts automatically resolved!"
    git commit --no-edit
    echo "Merge commit completed successfully."
else
    echo "Remaining conflicts to resolve manually or via agent runbook:"
    echo "${REMAINING_CONFLICTS}"
    echo "Refer to SKILL.md for resolution guidelines on each conflicting file."
    exit 1
fi
