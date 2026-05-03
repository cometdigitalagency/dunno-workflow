#!/usr/bin/env bats

load test_helper

@test "init: creates workflow.yaml in current directory" {
    run run_in_dir "$TEST_WORK_DIR" init
    [ "$status" -eq 0 ]
    [ -f "$TEST_WORK_DIR/workflow.yaml" ]
}

@test "init: creates tickets directory" {
    run run_in_dir "$TEST_WORK_DIR" init
    [ "$status" -eq 0 ]
    [ -d "$TEST_WORK_DIR/tickets" ]
}

@test "init: creates ticket template" {
    run run_in_dir "$TEST_WORK_DIR" init
    [ "$status" -eq 0 ]
    [ -f "$TEST_WORK_DIR/tickets/TEMPLATE.md" ]
}

@test "init: created workflow.yaml is valid" {
    run_in_dir "$TEST_WORK_DIR" init
    run run_in_dir "$TEST_WORK_DIR" validate
    [ "$status" -eq 0 ]
    [[ "$output" == *"workflow.yaml is valid"* ]]
}

@test "init: output confirms creation" {
    run run_in_dir "$TEST_WORK_DIR" init
    [ "$status" -eq 0 ]
    [[ "$output" == *"Created workflow.yaml"* ]]
}

@test "init: fails if workflow.yaml already exists and suggests --upgrade" {
    touch "$TEST_WORK_DIR/workflow.yaml"
    run run_in_dir "$TEST_WORK_DIR" init
    [ "$status" -ne 0 ]
    [[ "$output" == *"already exists"* ]]
    [[ "$output" == *"--upgrade"* ]]
}

@test "init: does not overwrite existing workflow.yaml" {
    echo "original content" > "$TEST_WORK_DIR/workflow.yaml"
    run run_in_dir "$TEST_WORK_DIR" init
    [ "$status" -ne 0 ]
    [[ "$(cat "$TEST_WORK_DIR/workflow.yaml")" == "original content" ]]
}

@test "init --upgrade: adds provider to agents without it" {
    use_fixture "minimal-valid.yaml"
    run run_in_dir "$TEST_WORK_DIR" init --upgrade
    [ "$status" -eq 0 ]
    [[ "$output" == *"Added provider: claude"* ]]
    # Verify provider was added
    grep -q 'provider: "claude"' "$TEST_WORK_DIR/workflow.yaml" || grep -q "provider: claude" "$TEST_WORK_DIR/workflow.yaml"
}

@test "init --upgrade: is idempotent" {
    use_fixture "multi-provider.yaml"
    run run_in_dir "$TEST_WORK_DIR" init --upgrade
    [ "$status" -eq 0 ]
    [[ "$output" == *"already up to date"* ]]
}

@test "init --upgrade: preserves existing project config" {
    use_fixture "minimal-valid.yaml"
    run_in_dir "$TEST_WORK_DIR" init --upgrade
    # Project name should still be the fixture's name
    grep -q 'name: minimal-test' "$TEST_WORK_DIR/workflow.yaml"
}

@test "init: ticket template has expected frontmatter" {
    run_in_dir "$TEST_WORK_DIR" init
    local template="$TEST_WORK_DIR/tickets/TEMPLATE.md"
    grep -q "status:" "$template"
    grep -q "title:" "$template"
    grep -q "## Summary" "$template"
    grep -q "## Notes (Optional)" "$template"
    grep -q "The architect will inspect the repo" "$template"
}
