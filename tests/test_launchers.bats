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

@test "auto_start: startup-team architect has waiting loop" {
    generate_all "startup-team.yaml"
    grep -q 'while true' "$(launcher architect)"
    grep -q 'No ready tickets found. Waiting for the PM to send one.' "$(launcher architect)"
}

@test "auto_start: parallel-workers lead checks ready tickets before Claude" {
    generate_all "parallel-workers.yaml"
    grep -q 'CMD_LIST_READY' "$(launcher lead)"
    grep -q '_has_ready_ticket' "$(launcher lead)"
}

@test "auto_start: bidirectional planner only retries on errors" {
    generate_all "bidirectional.yaml"
    grep -q 'Session ended with error. Retrying in 5s' "$(launcher planner)"
}

@test "auto_start: checks for pending trigger and ready tickets before Claude" {
    generate_all "startup-team.yaml"
    grep -q 'TRIGGER_FILE' "$(launcher architect)"
    grep -q 'PENDING_MSG' "$(launcher architect)"
    grep -q '_has_ready_ticket' "$(launcher architect)"
}

@test "auto_start: writes .state file" {
    generate_all "startup-team.yaml"
    grep -q 'STATE_HELPER' "$(launcher architect)"
    grep -q "running \"initial planning\"" "$(launcher architect)"
    grep -q "idle \"waiting\"" "$(launcher architect)"
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
    ls "$TEST_WORK_DIR/.team-prompts/triggers/api.from-"*.trigger >/dev/null 2>&1
    ls "$TEST_WORK_DIR/.team-prompts/triggers/web.from-"*.trigger >/dev/null 2>&1
    ls "$TEST_WORK_DIR/.team-prompts/triggers/reviewer.from-"*.trigger >/dev/null 2>&1
}

@test "send: bidirectional impl can send to verifier and vice versa" {
    generate_all "bidirectional.yaml"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" VERIFIER "DONE-impl: finished"
    ls "$TEST_WORK_DIR/.team-prompts/triggers/verifier.from-"*.trigger >/dev/null 2>&1
    rm -f "$TEST_WORK_DIR/.team-prompts/triggers/verifier.from-"*.trigger
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" IMPL "BUG: test failure"
    ls "$TEST_WORK_DIR/.team-prompts/triggers/impl.from-"*.trigger >/dev/null 2>&1
}

@test "send: DONE message creates done-sent marker across fixtures" {
    generate_all "parallel-workers.yaml"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" LEAD "DONE-api: endpoint done"
    [ -f "$TEST_WORK_DIR/.team-prompts/triggers/lead.done-sent" ]
}

# ══════════════════════════════════════════════════════════════════
# Dashboard generation is tmux-based in source
# ══════════════════════════════════════════════════════════════════

@test "dashboard: tmux is required for dashboard panes" {
    grep -q 'tmux is required for dashboard panes' "$DUNNO_WORKFLOW"
}

@test "dashboard: generates tmux-backed status script" {
    grep -q 'dashboard-status.sh' "$DUNNO_WORKFLOW"
    grep -q 'tmux new-session -d -s "\\$SESSION"' "$DUNNO_WORKFLOW"
}

@test "dashboard: debug logs use tmux instead of python screen scraping" {
    grep -q 'dashboard-logs.sh' "$DUNNO_WORKFLOW"
    ! grep -q 'screen-logger.py' "$DUNNO_WORKFLOW"
}

@test "dashboard: status pane no longer uses python renderer" {
    ! grep -q 'status-panel.py' "$DUNNO_WORKFLOW"
}

# ══════════════════════════════════════════════════════════════════
# Multi-provider support
# ══════════════════════════════════════════════════════════════════

@test "provider: claude worker passes --model flag" {
    generate_all "multi-provider.yaml"
    grep -q '\-\-model' "$(launcher lead)"
}

@test "provider: codex worker uses codex exec" {
    generate_all "multi-provider.yaml"
    grep -q 'codex exec' "$(launcher worker)"
}

@test "provider: codex worker uses conditional provider branching" {
    generate_all "multi-provider.yaml"
    grep -q 'if \[ "\$_PROVIDER" = "codex" \]' "$(launcher worker)"
}

@test "provider: codex worker has _PROVIDER=codex" {
    generate_all "multi-provider.yaml"
    grep -q "_PROVIDER='codex'" "$(launcher worker)"
}

@test "provider: claude agent has _PROVIDER=claude" {
    generate_all "multi-provider.yaml"
    grep -q "_PROVIDER='claude'" "$(launcher lead)"
}

@test "provider: codex worker has correct model" {
    generate_all "multi-provider.yaml"
    grep -q "_MODEL='o3'" "$(launcher worker)"
}

@test "provider: codex worker has workspace-write sandbox" {
    generate_all "multi-provider.yaml"
    grep -q "_CODEX_SANDBOX='workspace-write'" "$(launcher worker)"
}

@test "provider: claude lead has read-only sandbox" {
    generate_all "multi-provider.yaml"
    grep -q "_CODEX_SANDBOX='read-only'" "$(launcher lead)"
}

@test "provider: default provider is claude when omitted" {
    generate_all "minimal-valid.yaml"
    grep -q "_PROVIDER='claude'" "$(launcher lead)"
}

@test "provider: multi-provider generates correct launcher count" {
    generate_all "multi-provider.yaml"
    local count
    count=$(ls "$TEST_WORK_DIR/.team-prompts"/run-*.sh | wc -l | tr -d ' ')
    [ "$count" -eq 2 ]
}
