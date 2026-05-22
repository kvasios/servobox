#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "expected output to contain '${needle}', got: ${haystack}"
  fi
}

# shellcheck source=../scripts/servobox-lib/testing.sh
source "${REPO_ROOT}/scripts/servobox-lib/testing.sh"

sample_output=$'T: 0 ( 1234) P:80 I:1000 C: 10000 Min:      2 Act:    3 Avg:    4 Max:      90\nT: 1 ( 1235) P:80 I:1000 C: 10000 Min:      3 Act:    4 Avg:    5 Max:     121'
summary="$(parse_cyclictest_results "${sample_output}")"

assert_contains "${summary}" "Threads parsed: 2"
assert_contains "${summary}" "Best Min: 2 us"
assert_contains "${summary}" "Avg of Avg: 4 us"
assert_contains "${summary}" "Worst Max: 121 us (T:1)"
assert_contains "${summary}" "TIMING INTERPRETATION"
assert_contains "${summary}" "HEADROOM: 1kHz loop: 879 us after Worst Max; 500Hz loop: 1879 us after Worst Max"
assert_contains "${summary}" "STATUS: Strong VM timing result"
assert_contains "${summary}" "Note: Compare Worst Max"
assert_contains "${summary}" "Safety: This is a host/VM timing check"

refresh_output=$'T: 0 ( 1234) P:80 I:1000 C: 10 Min:      2 Act:    3 Avg:    4 Max:      90\rT: 0 ( 1234) P:80 I:1000 C: 20 Min:      2 Act:    3 Avg:    4 Max:      75'
refresh_summary="$(parse_cyclictest_results "${refresh_output}")"
assert_contains "${refresh_summary}" "Threads parsed: 1"
assert_contains "${refresh_summary}" "Worst Max: 75 us (T:0)"

marginal_output=$'T: 0 ( 1234) P:80 I:1000 C: 10000 Min:      2 Act:    3 Avg:    4 Max:     750'
marginal_summary="$(parse_cyclictest_results "${marginal_output}")"
assert_contains "${marginal_summary}" "STATUS: Marginal for strict 1kHz hard RT work"

[[ "$(first_cpulist_cpu "2-7")" == "2" ]] || fail "range cpulist did not resolve to first CPU"
[[ "$(first_cpulist_cpu "4,6-8")" == "4" ]] || fail "comma cpulist did not resolve to first CPU"

STRESS_PROFILE="cyclic"
validate_stress_profile
[[ "${STRESS_PROFILE}" == "cyclic" ]] || fail "cyclic stress profile was not accepted"

echo "latency parse tests passed"
