#!/usr/bin/env bats

load test_helper

GENERATE_HELPER="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/generate_prompts_helper.sh"

setup_pm_env() {
    use_fixture "startup-team-codex.yaml"
    mkdir -p "$TEST_WORK_DIR/tickets" "$TEST_WORK_DIR/test-bin"

    cat > "$TEST_WORK_DIR/tickets/1001.md" <<'EOF'
---
id: 1
title: Ready Ticket
status: ready
---

## Summary
Ready work item.
EOF

    cat > "$TEST_WORK_DIR/tickets/1002.md" <<'EOF'
---
id: 2
title: In Progress Ticket
status: in-progress
---

## Summary
Stale work item.
EOF

    cat > "$TEST_WORK_DIR/test-bin/codex" <<'EOF'
#!/bin/bash
cat >/tmp/dunno-pm-codex-last-input.txt
echo "stub llm output"
EOF
    chmod +x "$TEST_WORK_DIR/test-bin/codex"

    PATH="$TEST_WORK_DIR/test-bin:$PATH" "$GENERATE_HELPER" "$TEST_WORK_DIR" >/dev/null
}

@test "pm-commands: file-ticket commands work end-to-end" {
    setup_pm_env

    run bash -lc "cd '$TEST_WORK_DIR' && PATH='$TEST_WORK_DIR/test-bin:$PATH' ./.team-prompts/run-pm.sh <<'EOF'
status
backlog
view 1
claim 1
comment 1 note from pm
stale
agents
tell dev hello worker
/bash pwd
hello llm
quit
EOF"

    [ "$status" -eq 0 ]
    [[ "$output" == *"#1 [ready] Ready Ticket"* ]]
    [[ "$output" == *"#2 [in-progress] In Progress Ticket"* ]]
    [[ "$output" == *"Ready work item."* ]]
    [[ "$output" == *"Done."* ]]
    [[ "$output" == *"Comment added."* ]]
    [[ "$output" == *"Sent to dev."* ]]
    [[ "$output" == *"$TEST_WORK_DIR"* ]]
    [[ "$output" == *"stub llm output"* ]]
    grep -q '^status: in-progress$' "$TEST_WORK_DIR/tickets/1001.md"
    [[ "$(cat "$TEST_WORK_DIR/tickets/1001.md")" == *"note from pm"* ]]
    ls "$TEST_WORK_DIR/.team-prompts/triggers/dev.from-"*.trigger >/dev/null 2>&1
}

@test "pm-commands: /bash rejects PM built-ins with guidance" {
    setup_pm_env

    run bash -lc "cd '$TEST_WORK_DIR' && PATH='$TEST_WORK_DIR/test-bin:$PATH' ./.team-prompts/run-pm.sh <<'EOF'
/bash status
quit
EOF"

    [ "$status" -eq 0 ]
    [[ "$output" == *"is a PM command. Run it without /bash."* ]]
}
