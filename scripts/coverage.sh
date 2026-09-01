#!/usr/bin/env bash
# Run the test suite with coverage, filter the report, and emit HTML when lcov
# is available.
#
#   scripts/coverage.sh
#   BRANCH_COVERAGE=1 scripts/coverage.sh
set -euo pipefail

if [[ "${BRANCH_COVERAGE:-0}" == "1" ]]; then
  flutter test --coverage --branch-coverage
else
  flutter test --coverage
fi

if command -v lcov >/dev/null 2>&1; then
  # Taproot uses no code generation, so there are no .g.dart/.freezed.dart files
  # to strip — only generated l10n and the tests themselves.
  lcov --remove coverage/lcov.info \
    '*/**/generated/*' \
    '*/**/l10n/*' \
    '*/**/*_test.dart' \
    -o coverage/lcov.info

  if command -v genhtml >/dev/null 2>&1; then
    genhtml coverage/lcov.info -o coverage/html
  fi

  lcov --summary coverage/lcov.info
else
  echo "lcov not installed; skipping HTML report and filtered summary."
fi
