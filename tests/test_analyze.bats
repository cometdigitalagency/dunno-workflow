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
