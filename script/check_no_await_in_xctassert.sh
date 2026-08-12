#!/usr/bin/env bash
#
# Fails if an `await` appears inside an XCTAssert autoclosure.
#
# `XCTAssertTrue(await somethingAsync())` does not compile: XCTest's assertion
# parameters are `@autoclosure () throws -> T`, which does not support
# concurrency. The fix is always the same — hoist the await into a `let` and
# assert on the result:
#
#     let ready = await waitForCondition { store.isReady }
#     XCTAssertTrue(ready)
#
# This exists because the mistake is easy to make, reads as obviously correct,
# and costs a full CI cycle to discover on a repo with no local Swift
# toolchain. It has broken the build three times.
#
# Usage: script/check_no_await_in_xctassert.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCOPE="$ROOT/ui/Tests"

if [[ ! -d "$SCOPE" ]]; then
    echo "✗ $SCOPE does not exist. Update this guard if the test tree moved."
    exit 1
fi

# Matches `XCTAssertAnything(await ...` and `XCTAssertAnything(try await ...`.
# Anchored on the open paren so an `await` in a later argument — a message
# string built from an async call, say — is not what this is about; that form
# is equally broken, and the same regex catches it because the autoclosure is
# the first argument in every XCTAssert overload that takes one.
violations="$(
    grep -rnE 'XCTAssert[A-Za-z]*\((try )?await ' "$SCOPE" --include='*.swift' || true
)"

if [[ -n "$violations" ]]; then
    echo "✗ 'await' inside an XCTAssert autoclosure — this does not compile."
    echo ""
    echo "$violations"
    echo ""
    echo "Hoist the await into a local first:"
    echo "    let value = await something()"
    echo "    XCTAssertTrue(value)"
    exit 1
fi

count=$(find "$SCOPE" -name '*.swift' | wc -l | tr -d ' ')
echo "✓ No 'await' inside an XCTAssert autoclosure ($count test file(s) checked)."
