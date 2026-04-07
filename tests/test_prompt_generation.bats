#!/usr/bin/env bats

load test_helper

GENERATE_HELPER="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/generate_prompts_helper.sh"

# ── Helper to generate prompts from a fixture ──
generate_from_fixture() {
    local fixture="$1"
    shift
    use_fixture "$fixture"
    "$GENERATE_HELPER" "$TEST_WORK_DIR" "$@"
}

# ── dunno-agents.yaml: system prompts ──

@test "prompt: generates system prompt for all 5 dunno-agents" {
    generate_from_fixture "dunno-agents.yaml"
    [ -f "$TEST_WORK_DIR/.team-prompts/pm-system.txt" ]
    [ -f "$TEST_WORK_DIR/.team-prompts/architect-system.txt" ]
    [ -f "$TEST_WORK_DIR/.team-prompts/backend-system.txt" ]
    [ -f "$TEST_WORK_DIR/.team-prompts/frontend-system.txt" ]
    [ -f "$TEST_WORK_DIR/.team-prompts/qa-system.txt" ]
}

@test "prompt: generates init prompt for all 5 dunno-agents" {
    generate_from_fixture "dunno-agents.yaml"
    [ -f "$TEST_WORK_DIR/.team-prompts/pm-init.txt" ]
    [ -f "$TEST_WORK_DIR/.team-prompts/architect-init.txt" ]
    [ -f "$TEST_WORK_DIR/.team-prompts/backend-init.txt" ]
    [ -f "$TEST_WORK_DIR/.team-prompts/frontend-init.txt" ]
    [ -f "$TEST_WORK_DIR/.team-prompts/qa-init.txt" ]
}

@test "prompt: PM system prompt contains role" {
    generate_from_fixture "dunno-agents.yaml"
    grep -q "Project Manager" "$TEST_WORK_DIR/.team-prompts/pm-system.txt"
}

@test "prompt: PM system prompt contains project name" {
    generate_from_fixture "dunno-agents.yaml"
    grep -q "dunno-agents" "$TEST_WORK_DIR/.team-prompts/pm-system.txt"
}

@test "prompt: PM system prompt contains workflow steps" {
    generate_from_fixture "dunno-agents.yaml"
    local prompt="$TEST_WORK_DIR/.team-prompts/pm-system.txt"
    grep -q "YOUR WORKFLOW" "$prompt"
    grep -q "1\." "$prompt"
}

@test "prompt: PM system prompt contains commands section" {
    generate_from_fixture "dunno-agents.yaml"
    grep -q "COMMANDS" "$TEST_WORK_DIR/.team-prompts/pm-system.txt"
    grep -q "status" "$TEST_WORK_DIR/.team-prompts/pm-system.txt"
    grep -q "tell" "$TEST_WORK_DIR/.team-prompts/pm-system.txt"
}

@test "prompt: PM system prompt has send-to-agent for other agents" {
    generate_from_fixture "dunno-agents.yaml"
    local prompt="$TEST_WORK_DIR/.team-prompts/pm-system.txt"
    grep -q "send-to-agent.sh.*ARCHITECT" "$prompt"
    grep -q "send-to-agent.sh.*BACKEND" "$prompt"
    grep -q "send-to-agent.sh.*FRONTEND" "$prompt"
    grep -q "send-to-agent.sh.*QA" "$prompt"
}

@test "prompt: PM system prompt does NOT have send-to-agent for itself" {
    generate_from_fixture "dunno-agents.yaml"
    ! grep -q "send-to-agent.sh.*PM " "$TEST_WORK_DIR/.team-prompts/pm-system.txt"
}

@test "prompt: architect system prompt contains dispatch rules" {
    generate_from_fixture "dunno-agents.yaml"
    local prompt="$TEST_WORK_DIR/.team-prompts/architect-system.txt"
    grep -q "DISPATCH ORDER" "$prompt"
    grep -q "PHASE 1" "$prompt"
    grep -q "PHASE 2" "$prompt"
}

@test "prompt: backend system prompt contains file ownership" {
    generate_from_fixture "dunno-agents.yaml"
    local prompt="$TEST_WORK_DIR/.team-prompts/backend-system.txt"
    grep -q "FILE OWNERSHIP" "$prompt"
    grep -q "agents/\*\*" "$prompt"
    grep -q "NEVER edit.*frontend" "$prompt"
}

@test "prompt: frontend system prompt has correct ownership" {
    generate_from_fixture "dunno-agents.yaml"
    local prompt="$TEST_WORK_DIR/.team-prompts/frontend-system.txt"
    grep -q "frontend/\*\*" "$prompt"
    grep -q "NEVER edit.*agents" "$prompt"
}

@test "prompt: worker agents have IMPORTANT section" {
    generate_from_fixture "dunno-agents.yaml"
    for agent in architect backend frontend qa; do
        grep -q "## IMPORTANT" "$TEST_WORK_DIR/.team-prompts/${agent}-system.txt"
    done
}

@test "prompt: interactive agent does NOT have IMPORTANT section" {
    generate_from_fixture "dunno-agents.yaml"
    ! grep -q "## IMPORTANT" "$TEST_WORK_DIR/.team-prompts/pm-system.txt"
}

@test "prompt: system prompts contain file ticket commands" {
    generate_from_fixture "dunno-agents.yaml"
    local prompt="$TEST_WORK_DIR/.team-prompts/pm-system.txt"
    grep -q "TICKET COMMANDS (source: file)" "$prompt"
    grep -q "grep -rl" "$prompt"
}

@test "prompt: QA rules are present" {
    generate_from_fixture "dunno-agents.yaml"
    local prompt="$TEST_WORK_DIR/.team-prompts/qa-system.txt"
    grep -q "RULES" "$prompt"
    grep -q "Always run tests" "$prompt"
}

# ── Init prompts ──

@test "prompt: PM default init contains greeting" {
    generate_from_fixture "dunno-agents.yaml"
    grep -q "Project Manager" "$TEST_WORK_DIR/.team-prompts/pm-init.txt"
}

@test "prompt: architect default init mentions tickets" {
    generate_from_fixture "dunno-agents.yaml"
    grep -q "ticket" "$TEST_WORK_DIR/.team-prompts/architect-init.txt"
}

@test "prompt: worker default init mentions event-driven" {
    generate_from_fixture "dunno-agents.yaml"
    grep -q "event-driven" "$TEST_WORK_DIR/.team-prompts/backend-init.txt"
    grep -q "event-driven" "$TEST_WORK_DIR/.team-prompts/frontend-init.txt"
    grep -q "event-driven" "$TEST_WORK_DIR/.team-prompts/qa-init.txt"
}

# ── Issue mode ──

@test "prompt: issue mode substitutes issue number in init" {
    generate_from_fixture "dunno-agents.yaml" --issue 42
    grep -q "42" "$TEST_WORK_DIR/.team-prompts/architect-init.txt"
}

@test "prompt: issue mode substitutes in PM init" {
    generate_from_fixture "dunno-agents.yaml" --issue 7
    grep -q "7" "$TEST_WORK_DIR/.team-prompts/pm-init.txt"
}

# ── GitHub ticket source ──

@test "prompt: github ticket commands use gh CLI" {
    generate_from_fixture "github-tickets.yaml"
    local prompt="$TEST_WORK_DIR/.team-prompts/pm-system.txt"
    grep -q "TICKET COMMANDS (source: github)" "$prompt"
    grep -q "gh issue" "$prompt"
    grep -q "myorg/myrepo" "$prompt"
}

@test "prompt: github ticket labels are correct" {
    generate_from_fixture "github-tickets.yaml"
    local prompt="$TEST_WORK_DIR/.team-prompts/pm-system.txt"
    grep -q "ready" "$prompt"
    grep -q "in-progress" "$prompt"
}

# ── Minimal config ──

@test "prompt: minimal config generates 2 agent prompts" {
    generate_from_fixture "minimal-valid.yaml"
    [ -f "$TEST_WORK_DIR/.team-prompts/lead-system.txt" ]
    [ -f "$TEST_WORK_DIR/.team-prompts/worker-system.txt" ]
    [ -f "$TEST_WORK_DIR/.team-prompts/lead-init.txt" ]
    [ -f "$TEST_WORK_DIR/.team-prompts/worker-init.txt" ]
}

@test "prompt: minimal lead can message worker" {
    generate_from_fixture "minimal-valid.yaml"
    grep -q "send-to-agent.sh.*WORKER" "$TEST_WORK_DIR/.team-prompts/lead-system.txt"
}

@test "prompt: minimal worker can message lead" {
    generate_from_fixture "minimal-valid.yaml"
    grep -q "send-to-agent.sh.*LEAD" "$TEST_WORK_DIR/.team-prompts/worker-system.txt"
}
