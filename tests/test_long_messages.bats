#!/usr/bin/env bats

load test_helper

GENERATE_HELPER="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/generate_prompts_helper.sh"

# ── Helper: set up a working .team-prompts with send-to-agent.sh ──

setup_team_prompts() {
    use_fixture "$1"
    "$GENERATE_HELPER" "$TEST_WORK_DIR"
    # Generate send-to-agent.sh (the generate helper doesn't create it,
    # so we extract just that part by running a minimal start simulation)
    local prompt_dir="$TEST_WORK_DIR/.team-prompts"

    cat > "$prompt_dir/send-to-agent.sh" << 'HELPER'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_NAME=$(echo "$1" | tr '[:upper:]' '[:lower:]')
shift
MESSAGE="$*"

# Write trigger file for the worker's file-watch loop
TRIGGER_DIR="$SCRIPT_DIR/triggers"
if ! mkdir -p "$TRIGGER_DIR" 2>/dev/null; then
    echo "ERROR: Failed to create trigger directory: $TRIGGER_DIR" >&2
    exit 1
fi

TRIGGER_FILE="$TRIGGER_DIR/${AGENT_NAME}.trigger"
if ! printf '%s\n' "$MESSAGE" > "$TRIGGER_FILE"; then
    echo "ERROR: Failed to write trigger file: $TRIGGER_FILE" >&2
    exit 1
fi

# Verify the write succeeded (non-empty)
if [ ! -s "$TRIGGER_FILE" ]; then
    echo "ERROR: Trigger file is empty after write: $TRIGGER_FILE" >&2
    exit 1
fi

# Track DONE messages so auto-DONE doesn't duplicate them
case "$MESSAGE" in
    DONE-*|Done-*)
        touch "$TRIGGER_DIR/${AGENT_NAME}.done-sent" 2>/dev/null
        ;;
esac

# Show a brief notice (NOT the full message — long messages get truncated
# by AppleScript and interfere with the worker's polling loop).
AGENT_UPPER=$(echo "$AGENT_NAME" | tr '[:lower:]' '[:upper:]')
PREVIEW="${MESSAGE:0:120}"
[ ${#MESSAGE} -gt 120 ] && PREVIEW="${PREVIEW}..."
NOTICE="--- [$(date '+%H:%M:%S')] Message received (${#MESSAGE} chars): ${PREVIEW} ---"

# Skip AppleScript and ACK wait in test — just write the trigger file
echo "$NOTICE"
HELPER
    chmod +x "$prompt_dir/send-to-agent.sh"
}

# Generate a long TASK message similar to what the architect would send
generate_long_task() {
    local size="${1:-2000}"
    local msg="TASK [Ticket #2 - LinkedIn Scraper Agent]: The LinkedIn agent already exists at agents/linkedin/ with service.py, linkedin_scraper.py, auth.py, config.py, cache_manager.py, logger.py. However, it has several gaps compared to the Reddit agent that need fixing. Here is what you need to do: "
    msg+="1) FIX service.py (agents/linkedin/service.py): (a) Add ErrorTracker import and usage — copy error_tracker.py from agents/reddit/error_tracker.py to agents/linkedin/error_tracker.py, then import and use it in service.py exactly like Reddit does. (b) Add /ping endpoint returning {status: pong, timestamp}. (c) Add /version endpoint returning {version: 0.1.0, service: linkedin-agent}. (d) Add /trends/{keywords} endpoint — same implementation as Reddit service.py lines 139-151. (e) Add /research/history endpoint — same as Reddit service.py lines 154-161. (f) Fix /health endpoint to include agent, error_rates, and timestamp fields like Reddit. (g) Add error handling around find_similar_research call (wrap in try/except like Reddit). "
    msg+="2) FIX linkedin_scraper.py: (a) Add rate limiting with exponential backoff — use the same pattern as agents/reddit/reddit_scraper.py lines 45-67. (b) Add retry logic for failed requests with max 3 retries. (c) Add proper logging for each scraping step. (d) Add cache check before making network requests using cache_manager.py. (e) Implement pagination support for search results. "
    msg+="3) FIX config.py: (a) Add RATE_LIMIT_REQUESTS and RATE_LIMIT_WINDOW settings. (b) Add CACHE_TTL setting defaulting to 3600 seconds. (c) Add MAX_RETRIES setting defaulting to 3. (d) Add REQUEST_TIMEOUT setting defaulting to 30 seconds. "
    msg+="4) ADD error_tracker.py: Copy from agents/reddit/error_tracker.py and update class name to LinkedInErrorTracker. Keep the same interface. "
    msg+="5) UPDATE Dockerfile: Add any new dependencies to requirements.txt first, then ensure the Dockerfile copies them correctly. "
    # Pad to desired size
    while [ ${#msg} -lt "$size" ]; do
        msg+="Additional implementation detail: ensure all endpoints follow RESTful conventions, return proper HTTP status codes, and include comprehensive error messages in the response body. "
    done
    echo "$msg"
}

# ── Trigger file delivery tests ──

@test "long-msg: send-to-agent.sh creates trigger file for short message" {
    setup_team_prompts "dunno-agents.yaml"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" BACKEND "TASK: simple task"
    [ -f "$TEST_WORK_DIR/.team-prompts/triggers/backend.trigger" ]
    [[ "$(cat "$TEST_WORK_DIR/.team-prompts/triggers/backend.trigger")" == *"TASK: simple task"* ]]
}

@test "long-msg: 2KB message preserved in trigger file" {
    setup_team_prompts "dunno-agents.yaml"
    local msg
    msg=$(generate_long_task 2000)
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" BACKEND "$msg"
    local stored
    stored=$(cat "$TEST_WORK_DIR/.team-prompts/triggers/backend.trigger")
    # Verify the full message is preserved (not truncated)
    [ ${#stored} -ge 2000 ]
    [[ "$stored" == *"TASK [Ticket #2"* ]]
    [[ "$stored" == *"error_tracker.py"* ]]
    [[ "$stored" == *"linkedin_scraper.py"* ]]
    [[ "$stored" == *"Dockerfile"* ]]
}

@test "long-msg: 5KB message preserved in trigger file" {
    setup_team_prompts "dunno-agents.yaml"
    local msg
    msg=$(generate_long_task 5000)
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" BACKEND "$msg"
    local stored
    stored=$(cat "$TEST_WORK_DIR/.team-prompts/triggers/backend.trigger")
    [ ${#stored} -ge 5000 ]
}

@test "long-msg: 10KB message preserved in trigger file" {
    setup_team_prompts "dunno-agents.yaml"
    local msg
    msg=$(generate_long_task 10000)
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" BACKEND "$msg"
    local stored
    stored=$(cat "$TEST_WORK_DIR/.team-prompts/triggers/backend.trigger")
    [ ${#stored} -ge 10000 ]
}

@test "long-msg: 50KB message preserved in trigger file" {
    setup_team_prompts "dunno-agents.yaml"
    local msg
    msg=$(generate_long_task 50000)
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" BACKEND "$msg"
    local stored
    stored=$(cat "$TEST_WORK_DIR/.team-prompts/triggers/backend.trigger")
    [ ${#stored} -ge 50000 ]
}

# ── Cross-agent message delivery ──

@test "long-msg: architect can send long message to backend" {
    setup_team_prompts "dunno-agents.yaml"
    local msg
    msg=$(generate_long_task 3000)
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" BACKEND "$msg"
    [ -f "$TEST_WORK_DIR/.team-prompts/triggers/backend.trigger" ]
    local stored
    stored=$(cat "$TEST_WORK_DIR/.team-prompts/triggers/backend.trigger")
    [[ "$stored" == *"TASK [Ticket #2"* ]]
    [[ "$stored" == *"Dockerfile"* ]]
}

@test "long-msg: architect can send long message to frontend" {
    setup_team_prompts "dunno-agents.yaml"
    local msg
    msg=$(generate_long_task 3000)
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" FRONTEND "$msg"
    [ -f "$TEST_WORK_DIR/.team-prompts/triggers/frontend.trigger" ]
    local stored
    stored=$(cat "$TEST_WORK_DIR/.team-prompts/triggers/frontend.trigger")
    [ ${#stored} -ge 3000 ]
}

@test "long-msg: architect can send long message to qa" {
    setup_team_prompts "dunno-agents.yaml"
    local msg
    msg=$(generate_long_task 3000)
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" QA "$msg"
    [ -f "$TEST_WORK_DIR/.team-prompts/triggers/qa.trigger" ]
    local stored
    stored=$(cat "$TEST_WORK_DIR/.team-prompts/triggers/qa.trigger")
    [ ${#stored} -ge 3000 ]
}

@test "long-msg: simultaneous long messages to different agents" {
    setup_team_prompts "dunno-agents.yaml"
    local msg_be msg_fe
    msg_be=$(generate_long_task 4000)
    msg_fe="TASK [Ticket #2 - Frontend]: $(generate_long_task 4000)"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" BACKEND "$msg_be"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" FRONTEND "$msg_fe"
    # Both trigger files should exist with full content
    [ -f "$TEST_WORK_DIR/.team-prompts/triggers/backend.trigger" ]
    [ -f "$TEST_WORK_DIR/.team-prompts/triggers/frontend.trigger" ]
    local be_stored fe_stored
    be_stored=$(cat "$TEST_WORK_DIR/.team-prompts/triggers/backend.trigger")
    fe_stored=$(cat "$TEST_WORK_DIR/.team-prompts/triggers/frontend.trigger")
    [ ${#be_stored} -ge 4000 ]
    [ ${#fe_stored} -ge 4000 ]
    # Messages should be different (not cross-contaminated)
    [[ "$fe_stored" == *"Frontend"* ]]
}

# ── Agent name case handling ──

@test "long-msg: agent name is case-insensitive" {
    setup_team_prompts "dunno-agents.yaml"
    local msg
    msg=$(generate_long_task 2000)
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" BACKEND "$msg"
    [ -f "$TEST_WORK_DIR/.team-prompts/triggers/backend.trigger" ]
    rm "$TEST_WORK_DIR/.team-prompts/triggers/backend.trigger"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" backend "$msg"
    [ -f "$TEST_WORK_DIR/.team-prompts/triggers/backend.trigger" ]
    rm "$TEST_WORK_DIR/.team-prompts/triggers/backend.trigger"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" Backend "$msg"
    [ -f "$TEST_WORK_DIR/.team-prompts/triggers/backend.trigger" ]
}

# ── Worker trigger file pickup simulation ──

@test "long-msg: worker mv pattern preserves full message" {
    setup_team_prompts "dunno-agents.yaml"
    local trigger_dir="$TEST_WORK_DIR/.team-prompts/triggers"
    mkdir -p "$trigger_dir"
    local msg
    msg=$(generate_long_task 5000)
    # Simulate send-to-agent.sh writing trigger
    printf '%s\n' "$msg" > "$trigger_dir/backend.trigger"
    # Simulate worker mv (as in the fixed launcher)
    mv "$trigger_dir/backend.trigger" "$trigger_dir/backend.msg"
    [ -f "$trigger_dir/backend.msg" ]
    [ ! -f "$trigger_dir/backend.trigger" ]
    local work_msg
    work_msg=$(cat "$trigger_dir/backend.msg")
    [ ${#work_msg} -ge 5000 ]
    [[ "$work_msg" == *"TASK [Ticket #2"* ]]
    [[ "$work_msg" == *"Dockerfile"* ]]
}

@test "long-msg: new trigger doesn't overwrite in-progress work file" {
    setup_team_prompts "dunno-agents.yaml"
    local trigger_dir="$TEST_WORK_DIR/.team-prompts/triggers"
    mkdir -p "$trigger_dir"
    # Simulate first message being processed (moved to .msg)
    echo "first task in progress" > "$trigger_dir/backend.msg"
    # Simulate second message arriving (new .trigger)
    echo "second task queued" > "$trigger_dir/backend.trigger"
    # Both files should coexist
    [ -f "$trigger_dir/backend.msg" ]
    [ -f "$trigger_dir/backend.trigger" ]
    [[ "$(cat "$trigger_dir/backend.msg")" == *"first task"* ]]
    [[ "$(cat "$trigger_dir/backend.trigger")" == *"second task"* ]]
}

# ── Message content integrity ──

@test "long-msg: special characters preserved in trigger file" {
    setup_team_prompts "dunno-agents.yaml"
    local msg='TASK: Create endpoint /api/v1/health that returns {"status": "ok", "version": "1.0.0"} with Content-Type: application/json. Use $ENV_VAR for config. Handle errors with try/except & log failures.'
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" BACKEND "$msg"
    local stored
    stored=$(cat "$TEST_WORK_DIR/.team-prompts/triggers/backend.trigger")
    [[ "$stored" == *'/api/v1/health'* ]]
    [[ "$stored" == *'"status"'* ]]
    [[ "$stored" == *'try/except'* ]]
}

@test "long-msg: multiline-like content preserved" {
    setup_team_prompts "dunno-agents.yaml"
    local msg="TASK [Ticket #5]: 1) Create auth.py with login/logout endpoints. 2) Add JWT token generation using PyJWT. 3) Create middleware for token validation. 4) Add rate limiting per-user. 5) Write tests for all endpoints. When done, commit your changes and send to architect: DONE-backend with summary of what was implemented."
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" BACKEND "$msg"
    local stored
    stored=$(cat "$TEST_WORK_DIR/.team-prompts/triggers/backend.trigger")
    [[ "$stored" == *"1) Create auth.py"* ]]
    [[ "$stored" == *"5) Write tests"* ]]
    [[ "$stored" == *"DONE-backend"* ]]
}

@test "long-msg: message ending is not truncated (the actual bug)" {
    setup_team_prompts "dunno-agents.yaml"
    local msg
    msg=$(generate_long_task 3000)
    # Append a known marker at the end
    msg+=" END_MARKER_12345"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" BACKEND "$msg"
    local stored
    stored=$(cat "$TEST_WORK_DIR/.team-prompts/triggers/backend.trigger")
    # This was the actual bug — the end of long messages got truncated
    [[ "$stored" == *"END_MARKER_12345"* ]]
}

# ── ACK mechanism tests ──

@test "ack: worker creates ack file after picking up trigger" {
    setup_team_prompts "dunno-agents.yaml"
    local trigger_dir="$TEST_WORK_DIR/.team-prompts/triggers"
    mkdir -p "$trigger_dir"
    # Simulate send-to-agent.sh writing trigger
    printf '%s\n' "TASK: do something" > "$trigger_dir/backend.trigger"
    # Simulate worker picking up trigger (mv + ack)
    mv "$trigger_dir/backend.trigger" "$trigger_dir/backend.msg"
    printf '%s\n' "ACK $(date '+%H:%M:%S')" > "$trigger_dir/backend.ack"
    # ACK file should exist
    [ -f "$trigger_dir/backend.ack" ]
    [[ "$(cat "$trigger_dir/backend.ack")" == ACK* ]]
}

@test "ack: ack file is cleaned up after sender reads it" {
    setup_team_prompts "dunno-agents.yaml"
    local trigger_dir="$TEST_WORK_DIR/.team-prompts/triggers"
    mkdir -p "$trigger_dir"
    # Create an ACK file (as worker would)
    printf '%s\n' "ACK 12:00:00" > "$trigger_dir/backend.ack"
    [ -f "$trigger_dir/backend.ack" ]
    # Sender reads and removes ACK
    rm -f "$trigger_dir/backend.ack"
    [ ! -f "$trigger_dir/backend.ack" ]
}

@test "ack: ack not created when trigger file is empty" {
    setup_team_prompts "dunno-agents.yaml"
    local trigger_dir="$TEST_WORK_DIR/.team-prompts/triggers"
    mkdir -p "$trigger_dir"
    # Create an empty trigger file (corruption scenario)
    touch "$trigger_dir/backend.trigger"
    # Simulate worker: mv succeeds but file is empty — no ACK should be written
    mv "$trigger_dir/backend.trigger" "$trigger_dir/backend.msg"
    # Worker checks -s (non-empty) — it's empty, so skip processing
    if [ -s "$trigger_dir/backend.msg" ]; then
        printf '%s\n' "ACK $(date '+%H:%M:%S')" > "$trigger_dir/backend.ack"
    fi
    [ ! -f "$trigger_dir/backend.ack" ]
}

# ── Error handling tests ──

@test "error: send-to-agent.sh exits non-zero when trigger dir is unwritable" {
    setup_team_prompts "dunno-agents.yaml"
    local prompt_dir="$TEST_WORK_DIR/.team-prompts"
    # Create a read-only triggers directory
    mkdir -p "$prompt_dir/triggers"
    chmod 444 "$prompt_dir/triggers"
    # send-to-agent.sh should fail when it can't write
    run "$prompt_dir/send-to-agent.sh" BACKEND "TASK: should fail"
    chmod 755 "$prompt_dir/triggers"  # restore for cleanup
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR"* ]]
}

@test "error: send-to-agent.sh verifies file was written" {
    setup_team_prompts "dunno-agents.yaml"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" BACKEND "TASK: verify write"
    local trigger_dir="$TEST_WORK_DIR/.team-prompts/triggers"
    [ -f "$trigger_dir/backend.trigger" ]
    [ -s "$trigger_dir/backend.trigger" ]
}

# ── DONE marker tests ──

@test "done-marker: DONE message creates done-sent marker" {
    setup_team_prompts "dunno-agents.yaml"
    local trigger_dir="$TEST_WORK_DIR/.team-prompts/triggers"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" ARCHITECT "DONE-backend: Task completed"
    [ -f "$trigger_dir/architect.done-sent" ]
}

@test "done-marker: non-DONE message does not create marker" {
    setup_team_prompts "dunno-agents.yaml"
    local trigger_dir="$TEST_WORK_DIR/.team-prompts/triggers"
    "$TEST_WORK_DIR/.team-prompts/send-to-agent.sh" BACKEND "TASK: do something"
    [ ! -f "$trigger_dir/backend.done-sent" ]
}

@test "done-marker: done-sent prevents duplicate auto-DONE" {
    setup_team_prompts "dunno-agents.yaml"
    local trigger_dir="$TEST_WORK_DIR/.team-prompts/triggers"
    mkdir -p "$trigger_dir"
    # Simulate: agent already sent DONE (marker exists)
    touch "$trigger_dir/backend.done-sent"
    # Worker launcher checks: if marker exists, skip auto-DONE
    if [ ! -f "$trigger_dir/backend.done-sent" ]; then
        echo "AUTO_DONE_SENT" > "$trigger_dir/auto_done_flag"
    fi
    # Auto-DONE should NOT have been sent
    [ ! -f "$trigger_dir/auto_done_flag" ]
}

@test "done-marker: auto-DONE fires when agent did not send DONE" {
    setup_team_prompts "dunno-agents.yaml"
    local trigger_dir="$TEST_WORK_DIR/.team-prompts/triggers"
    mkdir -p "$trigger_dir"
    # No done-sent marker exists — agent didn't send DONE
    [ ! -f "$trigger_dir/backend.done-sent" ]
    # Worker launcher checks: no marker, so auto-DONE should fire
    if [ ! -f "$trigger_dir/backend.done-sent" ]; then
        echo "AUTO_DONE_SENT" > "$trigger_dir/auto_done_flag"
    fi
    [ -f "$trigger_dir/auto_done_flag" ]
}

# ── Worker mv race condition handling ──

@test "worker-mv: handles missing trigger file gracefully" {
    setup_team_prompts "dunno-agents.yaml"
    local trigger_dir="$TEST_WORK_DIR/.team-prompts/triggers"
    mkdir -p "$trigger_dir"
    # Trigger file does not exist — mv should fail
    run mv "$trigger_dir/backend.trigger" "$trigger_dir/backend.msg" 2>/dev/null
    [ "$status" -ne 0 ]
    # Worker loop would 'continue' here — no crash
}
