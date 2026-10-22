#!/bin/sh
# Entrypoint for the GitHub Pages deploy container.
# Expects: GITHUB_TOKEN (required), GITHUB_REPO="owner/repo" (required),
#          PAGES_BRANCH (default: gh-pages).
# Pushes /app/dist (mounted) to the Pages branch and enables Pages via the
# GitHub API. Prints the resulting base URL.
set -e

if [ -z "$GITHUB_TOKEN" ]; then
  echo "ERROR: GITHUB_TOKEN is required (a PAT with 'Contents: Read and write' and 'Pages: Read and write')." >&2
  exit 2
fi
if [ -z "$GITHUB_REPO" ]; then
  echo "ERROR: GITHUB_REPO is required, e.g. owner/druk-keys." >&2
  exit 2
fi

PAGES_BRANCH="${PAGES_BRANCH:-gh-pages}"
OWNER="$(echo "$GITHUB_REPO" | cut -d/ -f1)"
REPO="$(echo "$GITHUB_REPO" | cut -d/ -f2)"
API="https://api.github.com/repos/$OWNER/$REPO"
CLONE_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git"

echo "[deploy] repo     : $GITHUB_REPO (branch: $PAGES_BRANCH)"
echo "[deploy] bundle   : /app/dist"

# repo reachable? (also surfaces bad token/repo early)
if ! curl -fsS -H "Authorization: token $GITHUB_TOKEN" "$API" >/dev/null; then
  echo "ERROR: cannot read $API — check GITHUB_TOKEN and GITHUB_REPO (repo must exist)." >&2
  exit 1
fi

WORK="$(mktemp -d)"
git clone --quiet "$CLONE_URL" "$WORK/repo"
cd "$WORK/repo"

if git ls-remote --quiet origin "$PAGES_BRANCH" | grep -q .; then
  git checkout --quiet -B "$PAGES_BRANCH" "origin/$PAGES_BRANCH"
else
  echo "[deploy] branch '$PAGES_BRANCH' does not exist yet — creating orphan branch"
  git checkout --quiet --orphan "$PAGES_BRANCH"
  git rm -rfq . 2>/dev/null || true
fi

# replace content with the new bundle (keep .git)
find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
cp -r /app/dist/. .

git add -A
if ! git diff --cached --quiet; then
  git -c user.name="druk-keys" -c user.email="keys@druk.local" commit -q -m "deploy key set $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[deploy] pushing to origin/$PAGES_BRANCH ..."
  git push --quiet origin "$PAGES_BRANCH"
else
  echo "[deploy] no changes vs current $PAGES_BRANCH — nothing to push"
fi

echo "[deploy] enabling GitHub Pages from branch '$PAGES_BRANCH' (root) ..."
if curl -fsS -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
    -d "{\"build_type\":\"legacy\",\"source\":{\"branch\":\"$PAGES_BRANCH\",\"path\":\"/\"}}" \
    "$API/pages" >/dev/null 2>&1; then
  echo "[deploy] Pages source configured."
else
  echo "[deploy] WARN: could not set Pages source via API — enable it manually:"
  echo "         https://github.com/$OWNER/$REPO/settings/pages"
  echo "         (Build and deployment: Source = Deploy from a branch, $PAGES_BRANCH / (root))"
fi

BASE="https://${OWNER}.github.io/${REPO}"
echo ""
echo "================================================================"
echo "[deploy] DONE — key set at (after Pages build finishes):"
echo "         $BASE/protocol/openid-connect/certs"
echo "         Consumers should use issuer (iss) base: $BASE"
echo "================================================================"
