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

# Recent sessions: newest 12 by frontmatter `updated`.
for f in "$SESSIONS"/*.md; do
  [ -f "$f" ] || continue
  printf '%s\x1f%s\x1f%s\n' \
    "$(grep -m1 '^updated:' "$f" | sed 's/^updated: *//')" \
    "$(grep -m1 '^project:' "$f" | sed 's/^project: *//')" \
    "$(grep -m1 '^distilled:' "$f" | sed 's/^distilled: *//')"
done 2>/dev/null | sort -r | head -12 | while IFS=$'\x1f' read -r upd proj dis; do
  jq -n --arg u "$upd" --arg p "$proj" --argjson d "$([ "$dis" = true ] && echo true || echo false)" \
    '{updated:$u, project:$p, distilled:$d}'
done | jq -s . > "$TMPD/recent_sessions.json"

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
  name=$(basename "$n" .md)
  summary=$(grep -h "\[\[$name\]\]" "$KNOWLEDGE"/global/INDEX.md "$KNOWLEDGE"/projects/*/INDEX.md 2>/dev/null \
    | head -1 | sed 's/.*—[[:space:]]*//')
  jq -n --arg name "$name" --arg scope "$scope" --arg summary "$summary" \
        --arg updated "$(date -r "$m" '+%Y-%m-%d' 2>/dev/null || echo '?')" \
        '{name:$name, scope:$scope, summary:$summary, updated:$updated}' >> "$TMPD/recent.jsonl"
done
jq -s . "$TMPD/recent.jsonl" > "$TMPD/recent.json"

# --- proposals ----------------------------------------------------------------
count_status() { grep -c "^- status: $1" "$PROPOSALS" 2>/dev/null || true; }
proposed=$(count_status proposed); proposed=${proposed:-0}
implemented=$(count_status implemented); implemented=${implemented:-0}
rejected=$(count_status rejected); rejected=${rejected:-0}
if [ -f "$PROPOSALS" ]; then
  awk '
    function flush(){ if (n != "") printf "%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\n", n, seen, what, scope, conf, st }
    /^## /           { flush(); n=substr($0,4); seen=what=scope=conf=st="" }
    /^- seen: /      { seen=substr($0,9) }
    /^- what: /      { what=substr($0,9) }
    /^- scope: /     { scope=substr($0,10) }
    /^- confidence: /{ conf=substr($0,15) }
    /^- status: /    { st=substr($0,11) }
    END { flush() }
  ' "$PROPOSALS"
else :; fi | while IFS=$'\x1f' read -r name seen what scope conf st; do
  jq -n --arg n "$name" --arg s "$seen" --arg w "$what" --arg c "$scope" --arg f "$conf" --arg t "$st" \
    '{name:$n, seen:$s, what:$w, scope:$c, confidence:$f, status:$t}'
done | jq -s . > "$TMPD/items.json"

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
  --slurpfile recent_sessions "$TMPD/recent_sessions.json" \
  --argjson proposed "$proposed" --argjson implemented "$implemented" --argjson rejected "$rejected" \
  --slurpfile items "$TMPD/items.json" \
  '{
    generated_at: $generated_at,
    sessions: { total: $total, undistilled: $undistilled, by_day: $by_day[0], recent: $recent_sessions[0] },
    runs: $runs[0],
    knowledge: { global: $global, projects: $projects[0], recent: $recent[0] },
    proposals: { proposed: $proposed, implemented: $implemented, rejected: $rejected, items: $items[0] }
  }' > "$TMPD/data.json"

awk '/^__DATA__$/{exit}1' "$TPL" > "$OUT.tmp"
cat "$TMPD/data.json" >> "$OUT.tmp"
awk 'p; /^__DATA__$/{p=1}' "$TPL" >> "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
echo "dashboard: $OUT"
