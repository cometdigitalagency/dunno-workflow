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
