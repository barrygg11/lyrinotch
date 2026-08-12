#!/usr/bin/env bash
# Fail if production Sources line coverage is below a threshold (default 25%).
set -euo pipefail

threshold="${1:-25}"
if ! [[ "$threshold" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "error: threshold must be numeric, got: $threshold" >&2
  exit 1
fi

if [[ -n "${COVERAGE_JSON:-}" ]]; then
  coverage_json="$COVERAGE_JSON"
else
  coverage_json="$(swift test --show-codecov-path)"
fi

if [[ ! -f "$coverage_json" ]]; then
  echo "error: coverage JSON not found at: $coverage_json" >&2
  echo "hint: run \`swift test --enable-code-coverage\` first, or set COVERAGE_JSON=…" >&2
  exit 1
fi

ruby -rjson -e '
  report = JSON.parse(File.read(ARGV.fetch(0)))
  threshold = Float(ARGV.fetch(1))
  files = report.fetch("data").flat_map { |entry| entry.fetch("files") }

  # Match absolute or repo-relative production sources; exclude Tests/.
  production = %r{(?:^|/)Sources/Lyrinotch(?:Core)?/}
  tests = %r{(?:^|/)Tests/}
  source_files = files.select { |file|
    name = file.fetch("filename").to_s
    name.match?(production) && !name.match?(tests)
  }

  if source_files.empty?
    sample = files.first(5).map { |f| f.fetch("filename") }
    abort("No production source coverage found (sample paths: #{sample.inspect})")
  end

  covered = source_files.sum { |file| file.dig("summary", "lines", "covered").to_i }
  total = source_files.sum { |file| file.dig("summary", "lines", "count").to_i }
  abort("No production source coverage found") if total.zero?

  percent = covered.fdiv(total) * 100
  puts format(
    "Production line coverage: %.2f%% (%d/%d lines in %d files), required: %.2f%%",
    percent, covered, total, source_files.size, threshold
  )
  exit(1) if percent < threshold
' "$coverage_json" "$threshold"
