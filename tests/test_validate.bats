#!/usr/bin/env bats

load test_helper

# ── Valid configs ──

@test "validate: dunno-agents workflow.yaml passes" {
    use_fixture "dunno-agents.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -eq 0 ]
    [[ "$output" == *"workflow.yaml is valid"* ]]
    [[ "$output" == *"dunno-agents"* ]]
}

@test "validate: minimal 2-agent config passes" {
    use_fixture "minimal-valid.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -eq 0 ]
    [[ "$output" == *"workflow.yaml is valid"* ]]
    [[ "$output" == *"minimal-test"* ]]
}

@test "validate: github ticket source passes" {
    use_fixture "github-tickets.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -eq 0 ]
    [[ "$output" == *"workflow.yaml is valid"* ]]
    [[ "$output" == *"github"* ]]
}

@test "validate: shows project name in output" {
    use_fixture "dunno-agents.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project: dunno-agents"* ]]
}

@test "validate: shows ticket source in output" {
    use_fixture "dunno-agents.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ticket source: file"* ]]
}

@test "validate: lists all agents" {
    use_fixture "dunno-agents.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -eq 0 ]
    [[ "$output" == *"pm"* ]]
    [[ "$output" == *"architect"* ]]
    [[ "$output" == *"backend"* ]]
    [[ "$output" == *"frontend"* ]]
    [[ "$output" == *"qa"* ]]
}

# ── Invalid configs ──

@test "validate: fails when project.name is empty" {
    use_fixture "missing-project.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"project.name"* ]]
}

@test "validate: fails when tickets.source is empty" {
    use_fixture "missing-tickets.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"tickets.source"* ]]
}

@test "validate: single agent with interactive passes" {
    use_fixture "one-agent.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    # Upstream removed min-agent-count check; 1 interactive agent is valid
    [ "$status" -eq 0 ]
}

@test "validate: fails with no interactive agent" {
    use_fixture "no-interactive.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"exactly one agent must have interactive: true"* ]]
}

@test "validate: reports error count" {
    use_fixture "missing-project.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"error(s)"* ]]
}

# ── Missing file ──

@test "validate: fails when workflow.yaml does not exist" {
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"workflow.yaml not found"* ]]
}

# ── YAML syntax errors ──

@test "validate: rejects bad indentation" {
    use_fixture "syntax-bad-indent.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"syntax errors"* ]]
}

@test "validate: rejects malformed YAML" {
    use_fixture "syntax-duplicate-key.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"syntax errors"* ]]
}

@test "validate: rejects unclosed quotes" {
    use_fixture "syntax-unclosed-quote.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"syntax errors"* ]]
}

@test "validate: rejects tab indentation" {
    use_fixture "syntax-tab-indent.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"syntax errors"* ]]
}

# ── Graph validation: errors ──

@test "validate: detects missing event definition" {
    use_fixture "graph-missing-event.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"not defined in events"* ]]
}

@test "validate: detects dead agent (receives event nobody sends)" {
    use_fixture "graph-dead-agent.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"dead agent"* ]]
}

@test "validate: detects direction inconsistency" {
    use_fixture "graph-bad-direction.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"disagrees"* ]]
}

@test "validate: detects unreachable agent" {
    use_fixture "graph-unreachable.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"unreachable"* ]]
}

@test "validate: detects self-loop" {
    use_fixture "graph-self-loop.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"self-loop"* ]]
}

# ── Graph validation: warnings (exit 0) ──

@test "validate: warns on orphaned event but passes" {
    use_fixture "graph-orphaned-event.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
    [[ "$output" == *"no agent references"* ]]
}

@test "validate: warns on unused send but passes" {
    use_fixture "graph-unused-send.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
    [[ "$output" == *"no other agent receives"* ]]
}

@test "validate: warns on event loop cycle" {
    use_fixture "graph-event-loop.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    # Has self-loop errors too (alpha and beta both send+receive ping)
    [ "$status" -ne 0 ]
    [[ "$output" == *"self-loop"* ]]
}

# ── Graph validation: clean pass ──

@test "validate: dunno-agents passes all graph checks" {
    use_fixture "dunno-agents.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -eq 0 ]
    [[ "$output" == *"Event Flow:"* ]]
    [[ "$output" != *"ERROR"* ]]
}

@test "validate: shows event flow rendering with arrows" {
    use_fixture "dunno-agents.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -eq 0 ]
    [[ "$output" == *"task:"* ]]
    [[ "$output" == *"──►"* ]]
}

@test "validate: --version flag works" {
    run "$DUNNO_WORKFLOW" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"dunno-workflow v"* ]]
}

@test "validate: -v flag works" {
    run "$DUNNO_WORKFLOW" -v
    [ "$status" -eq 0 ]
    [[ "$output" == *"dunno-workflow v"* ]]
}

# ── Provider validation ──

@test "validate: rejects invalid provider" {
    use_fixture "invalid-provider.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid provider"* ]]
}

@test "validate: multi-provider config passes" {
    use_fixture "multi-provider.yaml"
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -eq 0 ]
    [[ "$output" == *"workflow.yaml is valid"* ]]
}
