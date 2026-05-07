#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

tests=(
  test.test_frontmatter
  test.test_events
  test.test_tree
  test.test_runtime
  test.test_planner
  test.test_opencode
)

exit_code=0

for mod in "${tests[@]}"; do
  file="${mod//\./\/}.lua"
  echo "━━━ $file"
  if ! nvim --headless -u NONE \
    -c "set rtp+=." \
    -c "lua local ok = require('$mod'); if not ok then vim.cmd('cq') end" \
    -c "qa!" 2>&1; then
    exit_code=1
  fi
  echo ""
done

if [ $exit_code -eq 0 ]; then
  echo "All suites passed."
else
  echo "Some suites FAILED."
fi

exit $exit_code
