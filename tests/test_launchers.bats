#!/usr/bin/env bats

load test_helper

GENERATE_HELPER="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/generate_prompts_helper.sh"

# ── Helpers ──

generate_all() {
    use_fixture "$1"
    "$GENERATE_HELPER" "$TEST_WORK_DIR"
}

launcher() {
    echo "$TEST_WORK_DIR/.team-prompts/run-${1}.sh"
}

# ══════════════════════════════════════════════════════════════════
# PM REPL — tested across all 3 fixtures
# ══════════════════════════════════════════════════════════════════

@test "pm-repl: startup-team PM has REPL loop" {
    generate_all "startup-team.yaml"
    grep -q 'read -r -p "PM> "' "$(launcher pm)"
}

@test "pm-repl: parallel-workers PM has REPL loop" {
    generate_all "parallel-workers.yaml"
    grep -q 'read -r -p "PM> "' "$(launcher pm)"
}

@test "pm-repl: bidirectional PM has REPL loop" {
    generate_all "bidirectional.yaml"
    grep -q 'read -r -p "PM> "' "$(launcher pm)"
}

# ── AGENT_LIST varies per fixture ──

@test "pm-repl: startup-team AGENT_LIST = architect dev qa" {
    generate_all "startup-team.yaml"
    grep -q 'AGENT_LIST="architect dev qa"' "$(launcher pm)"
}

@test "pm-repl: parallel-workers AGENT_LIST = lead api web reviewer" {
    generate_all "parallel-workers.yaml"
    grep -q 'AGENT_LIST="lead api web reviewer"' "$(launcher pm)"
}

@test "pm-repl: bidirectional AGENT_LIST = planner impl verifier" {
    generate_all "bidirectional.yaml"
    grep -q 'AGENT_LIST="planner impl verifier"' "$(launcher pm)"
}

# ── PM commands ──

@test "pm-repl: PM has agents command" {
    generate_all "startup-team.yaml"
    grep -q 'agents|team)' "$(launcher pm)"
}

@test "pm-repl: PM has tell command with validation" {
    generate_all "startup-team.yaml"
    grep -q 'Unknown agent' "$(launcher pm)"
    grep -q 'Available:' "$(launcher pm)"
}

@test "pm-repl: PM has help command" {
    generate_all "startup-team.yaml"
    grep -q 'help)' "$(launcher pm)"
}

@test "pm-repl: PM has LLM fallback" {
    generate_all "startup-team.yaml"
    grep -q 'claude -p' "$(launcher pm)"
}

@test "pm-repl: PM embeds ticket commands" {
    generate_all "startup-team.yaml"
    grep -q 'CMD_LIST_OPEN=' "$(launcher pm)"
    grep -q 'CMD_CLOSE=' "$(launcher pm)"
    grep -q 'CMD_VIEW=' "$(launcher pm)"
}

@test "pm-repl: PM does NOT use exec claude" {
    generate_all "startup-team.yaml"
    ! grep -q 'exec claude' "$(launcher pm)"
}

# ── PM agents command checks trigger files ──

@test "pm-repl: agents command checks .msg for working" {
    generate_all "startup-team.yaml"
    grep -q '\.msg"' "$(launcher pm)"
    grep -q 'working' "$(launcher pm)"
}

@test "pm-repl: agents command checks .trigger for pending" {
    generate_all "startup-team.yaml"
    grep -q '\.trigger"' "$(launcher pm)"
    grep -q 'pending' "$(launcher pm)"
}

@test "pm-repl: agents command checks .done-sent for done" {
    generate_all "startup-team.yaml"
    grep -q '\.done-sent"' "$(launcher pm)"
    grep -q 'done' "$(launcher pm)"
}

# ══════════════════════════════════════════════════════════════════
# Worker launchers — tested across all 3 fixtures
# ══════════════════════════════════════════════════════════════════

@test "worker: startup-team dev has event-driven loop" {
    generate_all "startup-team.yaml"
    grep -q 'Event-driven loop' "$(launcher dev)"
}

@test "worker: parallel-workers api has event-driven loop" {
    generate_all "parallel-workers.yaml"
    grep -q 'Event-driven loop' "$(launcher api)"
}

@test "worker: bidirectional impl has event-driven loop" {
    generate_all "bidirectional.yaml"
    grep -q 'Event-driven loop' "$(launcher impl)"
}

@test "worker: writes ACK file after trigger pickup" {
    generate_all "startup-team.yaml"
    grep -q '\.ack"' "$(launcher dev)"
    grep -q 'ACK' "$(launcher dev)"
}

@test "worker: writes .state on working" {
    generate_all "startup-team.yaml"
    grep -q 'working.*date +%s' "$(launcher dev)"
}

@test "worker: writes .state on idle" {
    generate_all "startup-team.yaml"
    grep -q 'idle.*date +%s' "$(launcher dev)"
}

@test "worker: conditional auto-DONE checks done-sent marker" {
    generate_all "startup-team.yaml"
    grep -q '\.done-sent"' "$(launcher dev)"
}

@test "worker: auto-DONE sends to correct auto_start agent" {
    generate_all "startup-team.yaml"
    grep -q 'DONE-dev.*auto-notify' "$(launcher dev)"
    grep -q 'send-to-agent.sh.*ARCHITECT' "$(launcher dev)"
}

@test "worker: parallel-workers api DONE goes to lead" {
    generate_all "parallel-workers.yaml"
    grep -q 'DONE-api.*auto-notify' "$(launcher api)"
    grep -q 'send-to-agent.sh.*LEAD' "$(launcher api)"
}

@test "worker: bidirectional impl DONE goes to planner" {
    generate_all "bidirectional.yaml"
    grep -q 'DONE-impl.*auto-notify' "$(launcher impl)"
    grep -q 'send-to-agent.sh.*PLANNER' "$(launcher impl)"
}

@test "worker: reviewer is a worker not auto_start" {
    generate_all "parallel-workers.yaml"
    grep -q 'Event-driven loop' "$(launcher reviewer)"
}

@test "worker: verifier is a worker not auto_start" {
    generate_all "bidirectional.yaml"
    grep -q 'Event-driven loop' "$(launcher verifier)"
}

# ══════════════════════════════════════════════════════════════════
# Auto-start (architect/lead/planner) launchers
# ══════════════════════════════════════════════════════════════════

@test "auto_start: startup-team architect has restart loop" {
    generate_all "startup-team.yaml"
    grep -q 'sleep 5' "$(launcher architect)"
    grep -q 'while true' "$(launcher architect)"
}

@test "auto_start: parallel-workers lead has restart loop" {
    generate_all "parallel-workers.yaml"
    grep -q 'sleep 5' "$(launcher lead)"
}

@test "auto_start: bidirectional planner has restart loop" {
    generate_all "bidirectional.yaml"
    grep -q 'sleep 5' "$(launcher planner)"
}

@test "auto_start: checks for pending trigger before restart" {
    generate_all "startup-team.yaml"
    grep -q 'TRIGGER_FILE' "$(launcher architect)"
    grep -q 'PENDING_MSG' "$(launcher architect)"
}

@test "auto_start: writes .state file" {
    generate_all "startup-team.yaml"
    grep -q '\.state"' "$(launcher architect)"
    grep -q 'working.*date +%s' "$(launcher architect)"
    grep -q 'idle.*date +%s' "$(launcher architect)"
}

@test "auto_start: has .work-done COMPLETE marker" {
    generate_all "startup-team.yaml"
    grep -q 'COMPLETE_MARKER' "$(launcher architect)"
    grep -q '.work-done' "$(launcher architect)"
}

@test "auto_start: auto_start is NOT a worker (no Event-driven loop)" {
    generate_all "startup-team.yaml"
    ! grep -q 'Event-driven loop' "$(launcher architect)"
}

# ══════════════════════════════════════════════════════════════════
# Cross-fixture: correct number of launchers generated
# ══════════════════════════════════════════════════════════════════

@test "cross: startup-team generates 4 launchers" {
    generate_all "startup-team.yaml"
    local count
    count=$(ls "$TEST_WORK_DIR/.team-prompts"/run-*.sh | wc -l | tr -d ' ')
    [ "$count" -eq 4 ]
}

@test "cross: parallel-workers generates 5 launchers" {
    generate_all "parallel-workers.yaml"
    local count
    count=$(ls "$TEST_WORK_DIR/.team-prompts"/run-*.sh | wc -l | tr -d ' ')
    [ "$count" -eq 5 ]
}

@test "cross: bidirectional generates 4 launchers" {
    generate_all "bidirectional.yaml"
    local count
    count=$(ls "$TEST_WORK_DIR/.team-prompts"/run-*.sh | wc -l | tr -d ' ')
    [ "$count" -eq 4 ]
}

@test "cross: all fixtures generate send-to-agent.sh" {
    for fixture in startup-team.yaml parallel-workers.yaml bidirectional.yaml; do
        generate_all "$fixture"
        [ -x "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" ]
    done
}

# ══════════════════════════════════════════════════════════════════
# send-to-agent.sh behavioral tests (from new fixtures)
# ══════════════════════════════════════════════════════════════════

@test "send: parallel-workers can send to all workers" {
    generate_all "parallel-workers.yaml"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" API "TASK: build endpoint"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" WEB "TASK: build ui"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" REVIEWER "REVIEW-REQUEST: check code"
    [ -f "$TEST_WORK_DIR/.team-prompts/triggers/api.trigger" ]
    [ -f "$TEST_WORK_DIR/.team-prompts/triggers/web.trigger" ]
    [ -f "$TEST_WORK_DIR/.team-prompts/triggers/reviewer.trigger" ]
}

@test "send: bidirectional impl can send to verifier and vice versa" {
    generate_all "bidirectional.yaml"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" VERIFIER "DONE-impl: finished"
    [ -f "$TEST_WORK_DIR/.team-prompts/triggers/verifier.trigger" ]
    rm "$TEST_WORK_DIR/.team-prompts/triggers/verifier.trigger"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" IMPL "BUG: test failure"
    [ -f "$TEST_WORK_DIR/.team-prompts/triggers/impl.trigger" ]
}

@test "send: DONE message creates done-sent marker across fixtures" {
    generate_all "parallel-workers.yaml"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" LEAD "DONE-api: endpoint done"
    [ -f "$TEST_WORK_DIR/.team-prompts/triggers/lead.done-sent" ]
}

# ══════════════════════════════════════════════════════════════════
# Dashboard (source template — legitimately checked in binary since
# screen-logger.py is a heredoc template, not fixture-generated)
# ══════════════════════════════════════════════════════════════════

@test "dashboard: render_dashboard function exists in source" {
    grep -q 'def render_dashboard' "$DUNNO_WORKFLOW"
}

@test "dashboard: uses ANSI cursor control" {
    grep -q '033\[s' "$DUNNO_WORKFLOW"
    grep -q '033\[H' "$DUNNO_WORKFLOW"
}

@test "dashboard: shows task counts" {
    grep -q 'done.*ongoing.*pending' "$DUNNO_WORKFLOW"
}

@test "dashboard: tracks session elapsed time" {
    grep -q 'SESSION_START' "$DUNNO_WORKFLOW"
}
