#!/usr/bin/env bash
# Promote this run's images: set their digests in merlion-bank-infra's values file, then open (or
# update) the promotion PR. Run by cd.yml's promote-staging job, from the infra checkout.
#
#   1. set the digests (update-digests.py); if nothing changed, close any stale promotion PR and stop
#   2. commit and force-push the promotion branch
#   3. list the app changes it adds, from the provenance of the version the env runs now
#   4. open or update the PR
#
# One open promotion PR at most: the branch is force-pushed from main each time, so the PR always holds
# exactly the newest digests and nothing else. It never merges: a teammate approves and merges.
#
# Environment (set by the workflow):
#   DIGESTS          JSON map image -> digest, from the summary job
#   GH_TOKEN         promotion App token, merlion-bank-infra only
#   APP_REPO_TOKEN   this repo's GITHUB_TOKEN, to read its attestations
#   APP_SLUG         the App's slug, for the commit author
#   INFRA            merlion-trust-bank-sg/merlion-bank-infra
#   BRANCH           promote/staging
#   VALUES           deploy/values-staging.yaml
#   APP_REPO_DIR     path to this repo's checkout (full history)
#   GITHUB_*         standard Actions variables (SHA, run ID, server URL, repository)
set -euo pipefail

env_name="${BRANCH#promote/}"
short="${GITHUB_SHA::7}"
app_url="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY"
commit_url="$app_url/commit/$GITHUB_SHA"
run_url="$app_url/actions/runs/$GITHUB_RUN_ID"
title="Promote merlion-bank-app $short to $env_name"

# The source commit recorded in a digest's build provenance (signed by cd when it built the image),
# or nothing. The API returns the bundle inline or only as bundle_url, depending on the version.
attested_commit() {
  local att bundle
  att="$(GH_TOKEN="$APP_REPO_TOKEN" gh api "repos/$GITHUB_REPOSITORY/attestations/$1" \
    --jq '.attestations[0]' 2>/dev/null)" || return 1
  [ -n "$att" ] && [ "$att" != null ] || return 1
  bundle="$(jq -c '.bundle // empty' <<<"$att")"
  if [ -z "$bundle" ]; then
    bundle="$(curl -fsSL "$(jq -r '.bundle_url' <<<"$att")" | { gzip -dc 2>/dev/null || cat; })" || return 1
  fi
  jq -r '.dsseEnvelope.payload' <<<"$bundle" | base64 -d |
    jq -r '.predicate.buildDefinition.resolvedDependencies[0].digest.gitCommit // empty'
}

# --- 1. Set the digests -----------------------------------------------------------------------------
digests_file="$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/digests.XXXXXX")"
printf '%s' "$DIGESTS" >"$digests_file"
python3 "$APP_REPO_DIR/.github/scripts/update-digests.py" "$VALUES" "$digests_file"

if git diff --quiet; then
  echo "$env_name already runs these images; nothing to promote." >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
  # An earlier promotion that never merged would now hold older digests
  pr="$(gh pr list --repo "$INFRA" --head "$BRANCH" --state open --json number --jq '.[0].number')"
  if [ -n "$pr" ]; then
    gh pr close "$pr" --repo "$INFRA" --delete-branch \
      --comment "Superseded: main already has the digests from merlion-bank-app $short."
  fi
  exit 0
fi

# --- 2. Commit and push the promotion branch ----------------------------------------------------------
user_id="$(gh api "/users/${APP_SLUG}[bot]" --jq .id)"
git config user.name "${APP_SLUG}[bot]"
git config user.email "${user_id}+${APP_SLUG}[bot]@users.noreply.github.com"
git switch -c "$BRANCH"
git commit -qam "$title"
git push --force origin "$BRANCH"

# --- 3. What this promotion adds -------------------------------------------------------------------
# Every app change merged since the version the environment runs now, found from the build provenance
# of its current frontend image. Only for the PR description: the infra repo's check verifies the
# signatures themselves.
current_digest="$(git show "origin/main:$VALUES" | grep -A1 -E '^  frontend:' |
  grep -oE 'sha256:[0-9a-f]{64}' | head -1)"
prev="$(attested_commit "$current_digest" || true)"

if [ -n "$prev" ] && git -C "$APP_REPO_DIR" merge-base --is-ancestor "$prev" "$GITHUB_SHA" 2>/dev/null; then
  since="Changes since $env_name's current version, [\`${prev::7}\`]($app_url/commit/$prev):"
  changes="$(git -C "$APP_REPO_DIR" log --first-parent --format="- [\`%h\`]($app_url/commit/%H) %s" \
    "$prev..$GITHUB_SHA" | head -30)"
else
  since="Changes ($env_name's current images have no build provenance, so only the newest is listed):"
  changes="- [\`$short\`]($commit_url) $(git -C "$APP_REPO_DIR" log -1 --format=%s "$GITHUB_SHA")"
fi

body="Promotes [merlion-bank-app@$short]($commit_url) to $env_name: changes only the image digests in \`$VALUES\`.

$since
$changes

Built, scanned, signed and pushed in [cd run $GITHUB_RUN_ID]($run_url). **Approve and merge to roll $env_name forward**; Argo CD syncs within ~3 minutes. A newer app merge updates this PR (and dismisses any approval) rather than opening another."

# --- 4. Open or update the PR -----------------------------------------------------------------------
pr="$(gh pr list --repo "$INFRA" --head "$BRANCH" --state open --json number --jq '.[0].number')"
if [ -z "$pr" ]; then
  gh pr create --repo "$INFRA" --base main --head "$BRANCH" --title "$title" --body "$body" >/dev/null
  pr="$(gh pr list --repo "$INFRA" --head "$BRANCH" --state open --json number --jq '.[0].number')"
else
  gh pr edit "$pr" --repo "$INFRA" --title "$title" --body "$body" >/dev/null
fi

echo "Promotion PR: https://github.com/$INFRA/pull/$pr" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
echo "number=$pr" >>"${GITHUB_OUTPUT:-/dev/null}"
