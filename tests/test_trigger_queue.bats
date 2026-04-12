#!/usr/bin/env bats

load test_helper

GENERATE_HELPER="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/generate_prompts_helper.sh"

setup_team_prompts() {
    use_fixture "$1"
    "$GENERATE_HELPER" "$TEST_WORK_DIR"
}

# ══════════════════════════════════════════════════════════════════
# Per-sender trigger file race condition tests
# ══════════════════════════════════════════════════════════════════

@test "trigger-queue: two DONE messages to same target create separate files" {
    setup_team_prompts "dunno-agents-codex.yaml"
    local trigger_dir="$TEST_WORK_DIR/.team-prompts/triggers"
    # Two different workers send DONE to architect
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" ARCHITECT "DONE-backend: backend done"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" ARCHITECT "DONE-frontend: frontend done"
    # Each gets its own per-sender trigger file
    [ -f "$trigger_dir/architect.from-backend.trigger" ]
    [ -f "$trigger_dir/architect.from-frontend.trigger" ]
    # Content is correct in each
    [[ "$(cat "$trigger_dir/architect.from-backend.trigger")" == *"DONE-backend"* ]]
    [[ "$(cat "$trigger_dir/architect.from-frontend.trigger")" == *"DONE-frontend"* ]]
}

@test "trigger-queue: non-DONE messages get unique trigger files" {
    setup_team_prompts "dunno-agents-codex.yaml"
    local trigger_dir="$TEST_WORK_DIR/.team-prompts/triggers"
    # Send two non-DONE messages to same target (different PIDs via subshells)
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" BACKEND "TASK: first task"
    sleep 1  # ensure different timestamp
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" BACKEND "TASK: second task"
    # Both should exist as separate per-sender files
    local count
    count=$(ls "$trigger_dir"/backend.from-msg-*.trigger 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -ge 2 ]
}

@test "trigger-queue: same sender DONE overwrites its own file" {
    setup_team_prompts "dunno-agents-codex.yaml"
    local trigger_dir="$TEST_WORK_DIR/.team-prompts/triggers"
    # Same sender sends DONE twice — should overwrite, not create two files
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" ARCHITECT "DONE-backend: first attempt"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" ARCHITECT "DONE-backend: second attempt"
    # Only one file for this sender
    [ -f "$trigger_dir/architect.from-backend.trigger" ]
    local count
    count=$(ls "$trigger_dir"/architect.from-backend.trigger 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -eq 1 ]
    # Content should be the latest message
    [[ "$(cat "$trigger_dir/architect.from-backend.trigger")" == *"second attempt"* ]]
}

@test "trigger-queue: DONE and non-DONE to same target coexist" {
    setup_team_prompts "dunno-agents-codex.yaml"
    local trigger_dir="$TEST_WORK_DIR/.team-prompts/triggers"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" ARCHITECT "DONE-backend: done"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" ARCHITECT "TASK: something else"
    # Both should exist — different sender patterns
    [ -f "$trigger_dir/architect.from-backend.trigger" ]
    ls "$trigger_dir"/architect.from-msg-*.trigger >/dev/null 2>&1
}

@test "trigger-queue: per-sender files don't interfere across targets" {
    setup_team_prompts "dunno-agents-codex.yaml"
    local trigger_dir="$TEST_WORK_DIR/.team-prompts/triggers"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" BACKEND "TASK: for backend"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" FRONTEND "TASK: for frontend"
    # Each target has its own trigger file
    ls "$trigger_dir"/backend.from-*.trigger >/dev/null 2>&1
    ls "$trigger_dir"/frontend.from-*.trigger >/dev/null 2>&1
    # No cross-contamination
    [[ "$(cat "$trigger_dir"/backend.from-*.trigger)" == *"for backend"* ]]
    [[ "$(cat "$trigger_dir"/frontend.from-*.trigger)" == *"for frontend"* ]]
}
