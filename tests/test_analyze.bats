#!/usr/bin/env bats

load test_helper

# Override setup to create .team-logs symlink from fixture
setup_analyze() {
    local fixture="$1"
    TEST_WORK_DIR="$(mktemp -d)"
    mkdir -p "$TEST_WORK_DIR/.team-logs"
    cp -r "$FIXTURES_DIR/$fixture" "$TEST_WORK_DIR/.team-logs/test-session"
}

# ── Clean session ──

@test "analyze: no issues found in clean session" {
    setup_analyze "logs-clean"
    run run_in_dir "$TEST_WORK_DIR" analyze --session test-session --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"No issues found"* ]]
}

# ── Stuck agent ──

@test "analyze: detects stuck agent (TASK but no DONE)" {
    setup_analyze "logs-stuck"
    run run_in_dir "$TEST_WORK_DIR" analyze --session test-session --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"STUCK AGENT"* ]]
    [[ "$output" == *"backend"* ]]
}

# ── DONE not delivered ──

@test "analyze: detects DONE not delivered to architect" {
    setup_analyze "logs-done-lost"
    run run_in_dir "$TEST_WORK_DIR" analyze --session test-session --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"DONE NOT DELIVERED"* ]]
}

# ── Session crash ──

@test "analyze: detects session crash with error traces" {
    setup_analyze "logs-crash"
    run run_in_dir "$TEST_WORK_DIR" analyze --session test-session --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"SESSION CRASH"* ]]
    [[ "$output" == *"backend"* ]]
}

# ── Permission blocked ──

@test "analyze: detects permission blocked" {
    setup_analyze "logs-permission"
    run run_in_dir "$TEST_WORK_DIR" analyze --session test-session --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"PERMISSION BLOCKED"* ]]
}

# ── Dispatch timeout ──

@test "analyze: detects dispatch timeout" {
    setup_analyze "logs-dispatch-timeout"
    run run_in_dir "$TEST_WORK_DIR" analyze --session test-session --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"DISPATCH TIMEOUT"* ]]
}

# ── Missing COMPLETE ──

@test "analyze: detects missing COMPLETE to PM" {
    setup_analyze "logs-no-complete"
    run run_in_dir "$TEST_WORK_DIR" analyze --session test-session --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"MISSING COMPLETE"* ]]
}

# ── Dry-run doesn't create issues ──

@test "analyze: dry-run shows DRY RUN label" {
    setup_analyze "logs-stuck"
    run run_in_dir "$TEST_WORK_DIR" analyze --session test-session --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"dry-run"* ]] || [[ "$output" == *"DRY RUN"* ]]
}

# ── No logs directory ──

@test "analyze: fails when no .team-logs/ exists" {
    run run_in_dir "$TEST_WORK_DIR" analyze
    [ "$status" -ne 0 ]
    [[ "$output" == *"No .team-logs/"* ]]
}

# ── Shows session info ──

@test "analyze: shows session name and log count" {
    setup_analyze "logs-clean"
    run run_in_dir "$TEST_WORK_DIR" analyze --session test-session --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-session"* ]]
    [[ "$output" == *"agent logs"* ]]
}

# ── Issue #3: Binary grep false positive for SESSION CRASH ──

@test "analyze: no false SESSION CRASH from binary artifacts in logs" {
    # Binary data (ANSI codes, null bytes, screen control chars) can cause
    # grep to treat logs as binary and produce false matches. The -a flag fix
    # ensures grep processes the file as text.
    setup_analyze "logs-binary"
    run run_in_dir "$TEST_WORK_DIR" analyze --session test-session --dry-run
    [ "$status" -eq 0 ]
    # Should NOT report SESSION CRASH — the binary fixtures have no real errors
    [[ "$output" != *"SESSION CRASH"* ]]
}

@test "analyze: no false SESSION CRASH from null bytes in logs" {
    # Create a fixture with embedded null bytes that would trip grep without -a
    TEST_WORK_DIR="$(mktemp -d)"
    mkdir -p "$TEST_WORK_DIR/.team-logs/test-session"
    printf 'Session started\n\x00\x01\x02 binary data \x00\nTask completed\n' \
        > "$TEST_WORK_DIR/.team-logs/test-session/backend.log"
    printf 'Session started\nAll good\n' \
        > "$TEST_WORK_DIR/.team-logs/test-session/pm.log"
    printf 'Session started\nAll good\n' \
        > "$TEST_WORK_DIR/.team-logs/test-session/architect.log"
    run run_in_dir "$TEST_WORK_DIR" analyze --session test-session --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" != *"SESSION CRASH"* ]]
}

# ── Issue #4: Binary grep false positive for PERMISSION BLOCKED ──

@test "analyze: no false PERMISSION BLOCKED from binary artifacts in logs" {
    setup_analyze "logs-binary"
    run run_in_dir "$TEST_WORK_DIR" analyze --session test-session --dry-run
    [ "$status" -eq 0 ]
    # Should NOT report PERMISSION BLOCKED — no real permission errors
    [[ "$output" != *"PERMISSION BLOCKED"* ]]
}

@test "analyze: no false PERMISSION BLOCKED from null bytes in logs" {
    TEST_WORK_DIR="$(mktemp -d)"
    mkdir -p "$TEST_WORK_DIR/.team-logs/test-session"
    # Null bytes can cause grep to misinterpret binary data as matching "denied" etc.
    printf 'Session started\n\x00\xff\xfe binary noise \x00\nTask completed\n' \
        > "$TEST_WORK_DIR/.team-logs/test-session/backend.log"
    printf 'Session started\nAll good\n' \
        > "$TEST_WORK_DIR/.team-logs/test-session/pm.log"
    printf 'Session started\nAll good\n' \
        > "$TEST_WORK_DIR/.team-logs/test-session/architect.log"
    run run_in_dir "$TEST_WORK_DIR" analyze --session test-session --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" != *"PERMISSION BLOCKED"* ]]
}

# ── Issue #9: ANSI escape sequences must not trigger false SESSION CRASH ──

@test "analyze: no false SESSION CRASH from ANSI color codes in logs" {
    # ANSI escape sequences (bold, color, reset) should not be misinterpreted
    # as error traces by the crash detector (issue #9)
    TEST_WORK_DIR="$(mktemp -d)"
    mkdir -p "$TEST_WORK_DIR/.team-logs/test-session"
    printf 'Session started\n\033[1;31mERROR_HIGHLIGHT\033[0m but not a real error\n' \
        > "$TEST_WORK_DIR/.team-logs/test-session/backend.log"
    printf 'Session started\n\033[0K\033[2J Screen clear\nTask completed\n' \
        > "$TEST_WORK_DIR/.team-logs/test-session/pm.log"
    printf 'Session started\nAll good\n' \
        > "$TEST_WORK_DIR/.team-logs/test-session/architect.log"
    run run_in_dir "$TEST_WORK_DIR" analyze --session test-session --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" != *"SESSION CRASH"* ]]
}

# ── Archive after issue creation ──

@test "analyze: archives session logs after creating issues" {
    setup_analyze "logs-stuck"
    unset GITHUB_TOKEN
    unset DUNNO_GITHUB_TOKEN
    run run_in_dir "$TEST_WORK_DIR" analyze --session test-session
    [ "$status" -eq 0 ]
    [[ "$output" == *"Archived"* ]]
    # Session should be moved to archived/
    [ -d "$TEST_WORK_DIR/.team-logs/archived/test-session" ]
    [ ! -d "$TEST_WORK_DIR/.team-logs/test-session" ]
}

@test "analyze: archives workflow.yaml alongside logs" {
    setup_analyze "logs-stuck"
    cp "$FIXTURES_DIR/minimal-valid.yaml" "$TEST_WORK_DIR/workflow.yaml"
    unset GITHUB_TOKEN
    unset DUNNO_GITHUB_TOKEN
    run run_in_dir "$TEST_WORK_DIR" analyze --session test-session
    [ "$status" -eq 0 ]
    [ -f "$TEST_WORK_DIR/.team-logs/archived/test-session/workflow.yaml" ]
}

@test "analyze: dry-run does not archive session logs" {
    setup_analyze "logs-stuck"
    run run_in_dir "$TEST_WORK_DIR" analyze --session test-session --dry-run
    [ "$status" -eq 0 ]
    # Session should remain in place
    [ -d "$TEST_WORK_DIR/.team-logs/test-session" ]
    [ ! -d "$TEST_WORK_DIR/.team-logs/archived/test-session" ]
}

@test "analyze: latest session skips archived directory" {
    setup_analyze "logs-stuck"
    # Create an archived directory that should be ignored
    mkdir -p "$TEST_WORK_DIR/.team-logs/archived"
    unset GITHUB_TOKEN
    unset DUNNO_GITHUB_TOKEN
    run run_in_dir "$TEST_WORK_DIR" analyze --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-session"* ]]
}

# ── Project label and workflow embed ──

@test "analyze: dry-run shows project label from workflow.yaml" {
    setup_analyze "logs-stuck"
    cp "$FIXTURES_DIR/minimal-valid.yaml" "$TEST_WORK_DIR/workflow.yaml"
    run run_in_dir "$TEST_WORK_DIR" analyze --session test-session --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"project:"* ]]
}

# ── Issues #3/#4: grep -a flag present in analyze functions ──

@test "analyze: grep uses -a flag in session crash detection" {
    # Verify the -a flag is used in analyze_session_crashes
    grep -q 'grep -qai' "$DUNNO_WORKFLOW"
    grep -q 'grep -ai' "$DUNNO_WORKFLOW"
}

@test "analyze: grep uses -a flag in permission block detection" {
    # Verify the -a flag is used in analyze_permission_blocks
    # The function uses grep -qai and grep -ai patterns
    local count
    count=$(grep -c 'grep -[qa]*ai' "$DUNNO_WORKFLOW" || true)
    [ "$count" -ge 2 ]
}
