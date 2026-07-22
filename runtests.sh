#!/bin/sh
# C89 Compiler Test Runner

PASSED=0
FAILED=0

echo "=== Running valid C tests ==="
for f in tests/valid/*.c; do
    name=$(basename "$f" .c)
    expected_exit=$(grep "EXPECT:EXIT=" "$f" | head -1 | sed 's/.*EXIT=//')
    expected_stdout=$(grep "EXPECT:STDOUT=" "$f" | head -1 | sed 's/.*STDOUT=//')

    printf "  %-30s " "$name:"
    
    if ! moon run --target native cmd/cc -- "$f" > /dev/null 2>&1; then
        echo "COMPILE FAIL"
        FAILED=$((FAILED+1))
        continue
    fi
    
    bin="${f%.c}"
    actual_stdout=$("./$bin" 2>/dev/null)
    actual_exit=$?
    
    if [ "$actual_exit" != "$expected_exit" ]; then
        echo "FAIL (got exit $actual_exit, expected $expected_exit)"
        FAILED=$((FAILED+1))
    elif [ -n "$expected_stdout" ] && [ "$actual_stdout" != "$expected_stdout" ]; then
        echo "FAIL (stdout mismatch: got '$actual_stdout', expected '$expected_stdout')"
        FAILED=$((FAILED+1))
    else
        echo "PASS"
        PASSED=$((PASSED+1))
    fi
    
    rm -f "$bin" "$bin.s"
done

echo ""
echo "=== Running invalid C tests ==="
for f in tests/invalid/*.c; do
    name=$(basename "$f" .c)
    printf "  %-30s " "$name:"
    
    if moon run --target native cmd/cc -- "$f" > /dev/null 2>&1; then
        echo "FAIL (should have been rejected)"
        FAILED=$((FAILED+1))
    else
        echo "PASS"
        PASSED=$((PASSED+1))
    fi
    bin="${f%.c}"
    rm -f "$bin" "$bin.s"
done

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ "$FAILED" -eq 0 ] || exit 1
