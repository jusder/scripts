#!/usr/bin/env zsh
set -u

GITHUB_USER="jusder"
ROOT="$HOME/Coding"

REPO_NAME="${1:-}"
VISIBILITY="${2:-private}"

usage() {
  echo "Usage: ${0:A:t} <repo-name> [public|private]"
  echo ""
  echo "  Creates a local git repo under $ROOT/<repo-name>,"
  echo "  initialises it, and creates a matching GitHub repo."
  echo "  Visibility defaults to private."
}

if [[ -z "$REPO_NAME" ]]; then
  usage
  exit 2
fi

if [[ "$VISIBILITY" != "public" && "$VISIBILITY" != "private" ]]; then
  echo "Error: visibility must be 'public' or 'private', got '$VISIBILITY'"
  usage
  exit 2
fi

LOCAL_PATH="$ROOT/$REPO_NAME"

if [[ -e "$LOCAL_PATH" ]]; then
  echo "Error: $LOCAL_PATH already exists."
  exit 1
fi

echo "Creating $LOCAL_PATH..."
if ! mkdir -p "$LOCAL_PATH"; then
  echo "Error: could not create directory"
  exit 1
fi

echo "Initialising git repo..."
if ! git -C "$LOCAL_PATH" init -q; then
  echo "Error: git init failed"
  exit 1
fi

git -C "$LOCAL_PATH" checkout -q -b main 2>/dev/null || git -C "$LOCAL_PATH" branch -m main 2>/dev/null

echo "Creating README.md..."
printf "# %s\n" "$REPO_NAME" > "$LOCAL_PATH/README.md"
git -C "$LOCAL_PATH" add README.md
if ! git -C "$LOCAL_PATH" commit -q -m "Initial commit"; then
  echo "Error: initial commit failed"
  exit 1
fi

echo "Creating GitHub repo ($VISIBILITY)..."
if ! gh repo create "$GITHUB_USER/$REPO_NAME" "--$VISIBILITY" --no-clone; then
  echo "Error: gh repo create failed"
  exit 1
fi

echo "Adding remote and pushing..."
git -C "$LOCAL_PATH" remote add origin "git@github.com:$GITHUB_USER/$REPO_NAME.git"
if ! git -C "$LOCAL_PATH" push -u origin main; then
  echo "Error: push failed"
  exit 1
fi

echo ""
echo "Done."
echo "  Local:  $LOCAL_PATH"
echo "  Remote: https://github.com/$GITHUB_USER/$REPO_NAME"
