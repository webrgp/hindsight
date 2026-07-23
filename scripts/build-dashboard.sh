#!/bin/bash
# hindsight :: dashboard builder — pure shell + jq, no LLM call.
# Computes one JSON data blob from the vault and injects it into the static
# template (templates/dashboard.html, line `__DATA__`). Self-contained output
# at $HINDSIGHT_HOME/dashboard.html, safe to open from file://.
# On-demand today (/hindsight:dashboard); distill can call it with one line later.
set -u

. "$(dirname "$0")/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$HERE/../templates/dashboard.html"
OUT="$HINDSIGHT_HOME/dashboard.html"
SESSIONS="$HINDSIGHT_HOME/sessions"
KNOWLEDGE="$HINDSIGHT_HOME/knowledge"
PROPOSALS="$HINDSIGHT_HOME/inbox/proposals.md"
RUNS="$HINDSIGHT_HOME/logs/runs.jsonl"
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

[ -d "$HINDSIGHT_HOME" ] || { echo "build-dashboard: no vault at $HINDSIGHT_HOME" >&2; exit 1; }

# --- sessions ---------------------------------------------------------------
total=$(find "$SESSIONS" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
undistilled=$(grep -rl '^distilled: false' "$SESSIONS" 2>/dev/null | wc -l | tr -d ' ')
grep -rh '^started:' "$SESSIONS" 2>/dev/null | sed 's/^started: //' | cut -c1-10 \
  | sort | uniq -c \
  | awk '{printf "{\"date\":\"%s\",\"count\":%d}\n", $2, $1}' \
  | jq -s . > "$TMPD/by_day.json"

# --- distill runs -----------------------------------------------------------
if [ -f "$RUNS" ]; then tail -50 "$RUNS" | jq -s . > "$TMPD/runs.json"
else echo '[]' > "$TMPD/runs.json"; fi

# --- knowledge --------------------------------------------------------------
global=$(find "$KNOWLEDGE/global" -name '*.md' ! -name 'INDEX.md' 2>/dev/null | wc -l | tr -d ' ')
: > "$TMPD/projects.jsonl"
for d in "$KNOWLEDGE/projects"/*/; do
  [ -d "$d" ] || continue
  n=$(find "$d" -name '*.md' ! -name 'INDEX.md' 2>/dev/null | wc -l | tr -d ' ')
  jq -n --arg p "$(basename "$d")" --argjson n "$n" '{project:$p, notes:$n}' >> "$TMPD/projects.jsonl"
done
jq -s . "$TMPD/projects.jsonl" > "$TMPD/projects.json"

# Recent notes: newest 10 by mtime, scope from the path.
: > "$TMPD/recent.jsonl"
find "$KNOWLEDGE" -name '*.md' ! -name 'INDEX.md' 2>/dev/null | while read -r n; do
  printf '%s\t%s\n' "$(stat -f '%m' "$n" 2>/dev/null || echo 0)" "$n"
done | sort -rn | head -10 | while IFS=$'\t' read -r m n; do
  case "$n" in
    (*/global/*) scope="global" ;;
    (*) scope=$(printf '%s' "$n" | sed 's|.*/projects/||; s|/.*||') ;;
  esac
  jq -n --arg name "$(basename "$n" .md)" --arg scope "$scope" \
        --arg updated "$(date -r "$m" '+%Y-%m-%d' 2>/dev/null || echo '?')" \
        '{name:$name, scope:$scope, updated:$updated}' >> "$TMPD/recent.jsonl"
done
jq -s . "$TMPD/recent.jsonl" > "$TMPD/recent.json"

# --- proposals ----------------------------------------------------------------
count_status() { grep -c "^- status: $1" "$PROPOSALS" 2>/dev/null || true; }
proposed=$(count_status proposed); proposed=${proposed:-0}
implemented=$(count_status implemented); implemented=${implemented:-0}
rejected=$(count_status rejected); rejected=${rejected:-0}
if [ -f "$PROPOSALS" ]; then
  awk '
    /^## /          {name=substr($0,4)}
    /^- seen: /     {seen[name]=substr($0,9)}
    /^- scope: /    {scope[name]=substr($0,10)}
    /^- status: proposed/ {printf "%s\t%s\t%s\n", name, seen[name], scope[name]}
  ' "$PROPOSALS"
else :; fi | while IFS=$'\t' read -r name seen scope; do
  jq -n --arg n "$name" --arg s "$seen" --arg c "$scope" '{name:$n, seen:$s, scope:$c}'
done | jq -s . > "$TMPD/pending.json"

# --- assemble + inject --------------------------------------------------------
jq -n \
  --arg generated_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --argjson total "${total:-0}" \
  --argjson undistilled "${undistilled:-0}" \
  --slurpfile by_day "$TMPD/by_day.json" \
  --slurpfile runs "$TMPD/runs.json" \
  --argjson global "${global:-0}" \
  --slurpfile projects "$TMPD/projects.json" \
  --slurpfile recent "$TMPD/recent.json" \
  --argjson proposed "$proposed" --argjson implemented "$implemented" --argjson rejected "$rejected" \
  --slurpfile pending "$TMPD/pending.json" \
  '{
    generated_at: $generated_at,
    sessions: { total: $total, undistilled: $undistilled, by_day: $by_day[0] },
    runs: $runs[0],
    knowledge: { global: $global, projects: $projects[0], recent: $recent[0] },
    proposals: { proposed: $proposed, implemented: $implemented, rejected: $rejected, pending: $pending[0] }
  }' > "$TMPD/data.json"

awk '/^__DATA__$/{exit}1' "$TPL" > "$OUT.tmp"
cat "$TMPD/data.json" >> "$OUT.tmp"
awk 'p; /^__DATA__$/{p=1}' "$TPL" >> "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
echo "dashboard: $OUT"
