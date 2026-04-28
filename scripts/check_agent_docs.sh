#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

required_files=(
  "AGENTS.md"
  "README.md"
  "docs/INDEX.md"
  "docs/agent-first/README.md"
  "docs/exec-plans/README.md"
  "docs/exec-plans/active/.gitkeep"
  "docs/exec-plans/completed/.gitkeep"
  "docs/exec-plans/tech-debt-tracker.md"
)

for path in "${required_files[@]}"; do
  if [[ ! -f "$path" ]]; then
    echo "missing required file: $path" >&2
    exit 1
  fi
done

grep -q "docs/INDEX.md" AGENTS.md || { echo "AGENTS.md must reference docs/INDEX.md" >&2; exit 1; }
grep -q "docs/agent-first/README.md" AGENTS.md || { echo "AGENTS.md must reference docs/agent-first/README.md" >&2; exit 1; }
grep -q "exec-plans" docs/INDEX.md || { echo "docs/INDEX.md must reference exec-plans" >&2; exit 1; }

echo "agent docs check: OK"
