#!/bin/bash
# generate_prompts_helper.sh — runs prompt generation without launching iTerm2
#
# Usage: ./generate_prompts_helper.sh <work_dir> [--test] [--issue N]
#
# Generates .team-prompts/ in work_dir but skips iTerm2 launch, cleanup,
# and GitHub label creation.

set -e

WORK_DIR="$1"
shift

cd "$WORK_DIR"

WORKFLOW_FILE="${WORK_DIR}/workflow.yaml"
ISSUE_NUM=""
TEST_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --test)  TEST_MODE=true; shift ;;
        --issue) ISSUE_NUM="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [ ! -f "$WORKFLOW_FILE" ]; then
    echo "ERROR: workflow.yaml not found"
    exit 1
fi

yq_get() { yq "$1" "$WORKFLOW_FILE"; }

PROJECT_NAME=$(yq_get '.project.name')
REPO_NAME=$(yq_get '.project.repo // ""')
TICKET_SOURCE=$(yq_get '.tickets.source')

AGENTS=()
while IFS= read -r agent; do
    AGENTS+=("$agent")
done < <(yq_get '.agents | keys | .[]')

INTERACTIVE_AGENT=""
WORKER_AGENTS=()
for agent in "${AGENTS[@]}"; do
    if [ "$(yq_get ".agents.$agent.interactive")" = "true" ]; then
        INTERACTIVE_AGENT="$agent"
    else
        WORKER_AGENTS+=("$agent")
    fi
done

PROMPT_DIR="${WORK_DIR}/.team-prompts"
mkdir -p "$PROMPT_DIR"

# Shared memory disabled by default in test helper
MEMORY_ENABLED="false"
CONTEXT_DIR=""
MEMORY_AGENTS_DOC="AGENTS.md"

# ── Ticket Source Commands ──
case "$TICKET_SOURCE" in
    github)
        gh_repo=$(yq_get '.tickets.github.repo // .project.repo')
        lbl_ready=$(yq_get '.tickets.github.labels.ready')
        lbl_inprog=$(yq_get '.tickets.github.labels.in_progress')
        lbl_done=$(yq_get '.tickets.github.labels.done')
        TICKET_CREATE="gh issue create --repo ${gh_repo} --title \"\$TITLE\" --label \"${lbl_ready},feature\" --body \"\$BODY\""
        TICKET_LIST_READY="gh issue list --repo ${gh_repo} --label ${lbl_ready} --state open --json number,title --jq '.[0].number // empty'"
        TICKET_VIEW="gh issue view \$N --repo ${gh_repo}"
        TICKET_CLAIM="gh issue edit \$N --repo ${gh_repo} --remove-label ${lbl_ready} --add-label ${lbl_inprog}"
        TICKET_COMMENT="gh issue comment \$N --repo ${gh_repo} --body \"\$MSG\""
        TICKET_CLOSE="gh issue close \$N --repo ${gh_repo} && gh issue edit \$N --repo ${gh_repo} --remove-label ${lbl_inprog} --add-label ${lbl_done}"
        TICKET_LIST_OPEN="gh issue list --repo ${gh_repo} --state open"
        TICKET_LIST_STALE="gh issue list --repo ${gh_repo} --label ${lbl_inprog} --state open --json number,title --jq '.[] | \"\\(.number) \\(.title)\"'"
        ;;
    file)
        dir=$(yq_get '.tickets.file.directory // "./tickets"')
        TICKET_CREATE="echo '---\nid: \$(ls ${dir}/*.md 2>/dev/null | wc -l | tr -d \" \")\ntitle: '\"\$TITLE\"'\nstatus: ready\nlabels: [feature]\ncreated: \$(date +%Y-%m-%d)\n---\n\n\$BODY' > '${dir}/\$(date +%s).md'"
        TICKET_LIST_READY="grep -rl 'status: ready' ${dir}/*.md 2>/dev/null | head -1"
        TICKET_VIEW="cat \$N"
        TICKET_CLAIM="sed -i '' 's/status: ready/status: in-progress/' \$N"
        TICKET_COMMENT="echo -e '\n---\n### \$MSG\n\$(date)' >> \$N"
        TICKET_CLOSE="sed -i '' 's/status: in-progress/status: done/' \$N"
        TICKET_LIST_OPEN="grep -rl 'status: \\(ready\\|in-progress\\)' ${dir}/*.md 2>/dev/null"
        TICKET_LIST_STALE="grep -rl 'status: in-progress' ${dir}/*.md 2>/dev/null"
        ;;
    *)
        TICKET_CREATE=""
        TICKET_LIST_READY=""
        TICKET_VIEW=""
        TICKET_CLAIM=""
        TICKET_COMMENT=""
        TICKET_CLOSE=""
        TICKET_LIST_OPEN=""
        TICKET_LIST_STALE=""
        ;;
esac

# ── Generate System Prompts ──
generate_system_prompt() {
    local agent="$1"
    local role description interactive
    role=$(yq_get ".agents.$agent.role")
    description=$(yq_get ".agents.$agent.description")
    interactive=$(yq_get ".agents.$agent.interactive")

    local prompt=""
    prompt+="You are the ${role} for the ${PROJECT_NAME} platform. ${description}\n\n"

    prompt+="## YOUR WORKFLOW\n"
    local step_num=1
    while IFS= read -r step; do
        step="${step//\{repo\}/$REPO_NAME}"
        prompt+="${step_num}. ${step}\n"
        ((step_num++))
    done < <(yq_get ".agents.$agent.workflow[]")
    prompt+="\n"

    prompt+="## COMMUNICATING WITH AGENTS\n"
    prompt+="You can send messages to any agent by running bash commands:\n"
    for other in "${AGENTS[@]}"; do
        if [ "$other" != "$agent" ]; then
            local other_upper
            other_upper=$(echo "$other" | tr '[:lower:]' '[:upper:]')
            prompt+="- Send message to ${other}: bash -c \"'${PROMPT_DIR}/send-to-agent.sh' ${other_upper} 'your message here'\"\n"
        fi
    done
    prompt+="\n"

    prompt+="## TICKET COMMANDS (source: ${TICKET_SOURCE})\n"
    prompt+="- Create ticket: ${TICKET_CREATE}\n"
    prompt+="- List ready tickets: ${TICKET_LIST_READY}\n"
    prompt+="- View ticket: ${TICKET_VIEW}\n"
    prompt+="- Claim ticket (mark in-progress): ${TICKET_CLAIM}\n"
    prompt+="- Comment on ticket: ${TICKET_COMMENT}\n"
    prompt+="- Close ticket (mark done): ${TICKET_CLOSE}\n"
    prompt+="- List open tickets: ${TICKET_LIST_OPEN}\n"
    prompt+="- List stale in-progress tickets: ${TICKET_LIST_STALE}\n"
    prompt+="\n"

    local rules_count
    rules_count=$(yq_get ".agents.$agent.rules | length")
    if [ "$rules_count" != "0" ]; then
        prompt+="## RULES\n"
        while IFS= read -r rule; do
            prompt+="- ${rule}\n"
        done < <(yq_get ".agents.$agent.rules[]")
        prompt+="\n"
    fi

    local owns_count never_count
    owns_count=$(yq_get ".agents.$agent.owns.paths | length")
    never_count=$(yq_get ".agents.$agent.owns.never_edit | length")
    if [ "$owns_count" != "0" ] || [ "$never_count" != "0" ]; then
        prompt+="## FILE OWNERSHIP\n"
        if [ "$owns_count" != "0" ]; then
            prompt+="You may edit files matching: "
            prompt+=$(yq_get ".agents.$agent.owns.paths | join(\", \")")
            prompt+="\n"
        fi
        if [ "$never_count" != "0" ]; then
            prompt+="You must NEVER edit: "
            prompt+=$(yq_get ".agents.$agent.owns.never_edit | join(\", \")")
            prompt+="\n"
        fi
        prompt+="\n"
    fi

    local cmds_count
    cmds_count=$(yq_get ".agents.$agent.commands // {} | length")
    if [ "$cmds_count" != "0" ]; then
        prompt+="## COMMANDS (when the user says these)\n"
        while IFS= read -r line; do
            local key="${line%%=*}"
            local val="${line#*=}"
            val="${val//\{repo\}/$REPO_NAME}"
            prompt+="- \"${key}\" → ${val}\n"
        done < <(yq_get ".agents.$agent.commands // {} | to_entries | .[] | .key + \"=\" + .value")
        prompt+="\n"
    fi

    local extra
    extra=$(yq_get ".agents.$agent.prompt_extra // \"\"")
    if [ -n "$extra" ] && [ "$extra" != "\"\"" ] && [ "$extra" != "" ]; then
        prompt+="\n${extra}\n"
    fi

    if [ "$interactive" != "true" ]; then
        prompt+="## IMPORTANT\n"
        prompt+="- If the PM sends you a message (stop, pause, status), handle it immediately.\n"
        prompt+="- ALWAYS post your done marker on the ticket when you finish your tasks.\n"
    fi

    printf '%b' "$prompt" > "$PROMPT_DIR/${agent}-system.txt"
}

# ── Generate Init Prompts ──
generate_init_prompt() {
    local agent="$1"
    local mode="default"
    [ "$TEST_MODE" = true ] && mode="test"
    [ -n "$ISSUE_NUM" ] && mode="issue"

    local init_text
    init_text=$(yq_get ".agents.$agent.init.$mode // .agents.$agent.init.default")

    if [ "$init_text" = "{default}" ]; then
        init_text=$(yq_get ".agents.$agent.init.default")
    fi

    init_text="${init_text//\{issue_num\}/$ISSUE_NUM}"
    init_text="${init_text//\{repo\}/$REPO_NAME}"

    printf '%s' "$init_text" > "$PROMPT_DIR/${agent}-init.txt"
}

# ── Tool Mapping ──
get_allowed_tools() {
    local agent="$1"
    local tools_list=""
    while IFS= read -r tool; do
        case "$tool" in
            read)          tools_list+="Read," ;;
            edit)          tools_list+="Edit," ;;
            write)         tools_list+="Write," ;;
            bash)          tools_list+="Bash(*)," ;;
            glob)          tools_list+="Glob," ;;
            grep)          tools_list+="Grep," ;;
            *)             ;;
        esac
    done < <(yq_get ".agents.$agent.tools[]" 2>/dev/null)
    echo "${tools_list%,}"
}

# Map workflow.yaml tools to Codex sandbox mode
get_codex_sandbox_mode() {
    local agent="$1"
    local has_write=false
    while IFS= read -r tool; do
        case "$tool" in
            edit|write) has_write=true ;;
        esac
    done < <(yq_get ".agents.$agent.tools[]" 2>/dev/null)
    if [ "$has_write" = true ]; then
        echo "workspace-write"
    else
        echo "read-only"
    fi
}

# ── Generate send-to-agent.sh (test version — no AppleScript/ACK) ──
generate_send_to_agent() {
    cat > "$PROMPT_DIR/send-to-agent.sh" << 'HELPER'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_NAME=$(echo "$1" | tr '[:upper:]' '[:lower:]')
shift
MESSAGE="$*"

TRIGGER_DIR="$SCRIPT_DIR/triggers"
if ! mkdir -p "$TRIGGER_DIR" 2>/dev/null; then
    echo "ERROR: Failed to create trigger directory: $TRIGGER_DIR" >&2
    exit 1
fi

# Per-sender trigger files to prevent race conditions.
case "$MESSAGE" in
    DONE-*|Done-*)
        SENDER=$(echo "$MESSAGE" | sed 's/^[Dd][Oo][Nn][Ee]-\([^:]*\).*/\1/' | tr '[:upper:]' '[:lower:]')
        TRIGGER_FILE="$TRIGGER_DIR/${AGENT_NAME}.from-${SENDER}.trigger"
        touch "$TRIGGER_DIR/${AGENT_NAME}.done-sent" 2>/dev/null
        ;;
    *)
        SENDER="msg-$(date +%s)-$$"
        TRIGGER_FILE="$TRIGGER_DIR/${AGENT_NAME}.from-${SENDER}.trigger"
        ;;
esac

if ! printf '%s\n' "$MESSAGE" > "$TRIGGER_FILE"; then
    echo "ERROR: Failed to write trigger file: $TRIGGER_FILE" >&2
    exit 1
fi

if [ ! -s "$TRIGGER_FILE" ]; then
    echo "ERROR: Trigger file is empty after write: $TRIGGER_FILE" >&2
    exit 1
fi

AGENT_UPPER=$(echo "$AGENT_NAME" | tr '[:lower:]' '[:upper:]')
PREVIEW="${MESSAGE:0:120}"
[ ${#MESSAGE} -gt 120 ] && PREVIEW="${PREVIEW}..."
echo "--- [$(date '+%H:%M:%S')] Message to ${AGENT_UPPER} (${#MESSAGE} chars): ${PREVIEW} ---"
HELPER
    chmod +x "$PROMPT_DIR/send-to-agent.sh"
}

# ── Generate Launchers ──
generate_launcher() {
    local agent="$1"
    local interactive
    interactive=$(yq_get ".agents.$agent.interactive")
    local label
    label=$(echo "$agent" | tr '[:lower:]' '[:upper:]')
    local allowed_tools
    allowed_tools=$(get_allowed_tools "$agent")
    local provider model codex_sandbox
    provider=$(yq_get ".agents.$agent.provider // \"claude\"")
    model=$(yq_get ".agents.$agent.model // \"\"")
    codex_sandbox=$(get_codex_sandbox_mode "$agent")

    # Find the auto_start agent for DONE callbacks
    local auto_start_agent="" auto_start_label=""
    for _a in "${AGENTS[@]}"; do
        if [ "$(yq_get ".agents.$_a.auto_start // false")" = "true" ]; then
            auto_start_agent="$_a"
            auto_start_label=$(echo "$_a" | tr '[:lower:]' '[:upper:]')
            break
        fi
    done

    local REPO_DIR="$WORK_DIR"

    if [ "$interactive" = "true" ]; then
        # Build agent list (non-interactive agents)
        local _agent_list=""
        for _a in "${AGENTS[@]}"; do
            [ "$_a" != "$agent" ] && _agent_list+="$_a "
        done
        _agent_list="${_agent_list% }"

        sed 's/^    //' > "$PROMPT_DIR/run-${agent}.sh" << LAUNCHER
    #!/bin/bash
    cd '${REPO_DIR}'
    printf '\033]0;${label}\007'
    SYSTEM_PROMPT=\$(cat '${PROMPT_DIR}/${agent}-system.txt')
    PROMPT_DIR='${PROMPT_DIR}'
    TRIGGER_DIR='${PROMPT_DIR}/triggers'
    mkdir -p "\$TRIGGER_DIR"
    _PROVIDER='${provider}'
    _MODEL='${model}'
    _CODEX_SANDBOX='${codex_sandbox}'

    AGENT_LIST="${_agent_list}"

    CMD_LIST_OPEN="${TICKET_LIST_OPEN}"
    CMD_LIST_READY="${TICKET_LIST_READY}"
    CMD_VIEW="${TICKET_VIEW}"
    CMD_CLAIM="${TICKET_CLAIM}"
    CMD_COMMENT="${TICKET_COMMENT}"
    CMD_CLOSE="${TICKET_CLOSE}"
    CMD_CREATE="${TICKET_CREATE}"
    CMD_LIST_STALE="${TICKET_LIST_STALE}"

    # REPL
    while true; do
        read -r -p "PM> " INPUT || break
        [ -z "\$INPUT" ] && continue
        case "\$INPUT" in
            help)
                echo "  status | backlog | view N | close N | claim N | tell agent msg | agents | ai prompt | quit"
                ;;
            status)
                eval "\$CMD_LIST_OPEN" 2>/dev/null || echo "(no tickets)"
                ;;
            agents|team)
                for _a in \$AGENT_LIST; do
                    if [ -f "\$TRIGGER_DIR/\${_a}.msg" ]; then
                        printf "  %-14s working\n" "\$_a"
                    elif [ -f "\$TRIGGER_DIR/\${_a}.trigger" ] || ls "\$TRIGGER_DIR/\${_a}".from-*.trigger >/dev/null 2>&1; then
                        printf "  %-14s pending\n" "\$_a"
                    elif [ -f "\$TRIGGER_DIR/\${_a}.done-sent" ]; then
                        printf "  %-14s done\n" "\$_a"
                    else
                        printf "  %-14s idle\n" "\$_a"
                    fi
                done
                ;;
            tell\ *)
                AGENT=\$(echo "\$INPUT" | awk '{print tolower(\$2)}')
                if ! echo " \$AGENT_LIST " | grep -q " \$AGENT "; then
                    echo "  Unknown agent: \$AGENT"
                    echo "  Available: \$AGENT_LIST"
                else
                    MSG=\$(echo "\$INPUT" | sed 's/^tell *[^ ]* *//')
                    AGENT_UPPER=\$(echo "\$AGENT" | tr '[:lower:]' '[:upper:]')
                    '\${PROMPT_DIR}/send-to-agent.sh' "\$AGENT_UPPER" "\$MSG"
                fi
                ;;
            ai\ *)
                PROMPT=\$(echo "\$INPUT" | sed 's/^ai *//')
                if [ "\$_PROVIDER" = "codex" ]; then
                    printf '%s\n\n---\n\n%s' "\$SYSTEM_PROMPT" "\$PROMPT" | codex exec -m "\$_MODEL" -s "\$_CODEX_SANDBOX" --full-auto -
                else
                    echo "\$PROMPT" | claude -p --model "\$_MODEL" --append-system-prompt "\$SYSTEM_PROMPT" --allowedTools "${allowed_tools}"
                fi
                ;;
            quit|exit) break ;;
            *)
                if [ "\$_PROVIDER" = "codex" ]; then
                    printf '%s\n\n---\n\n%s' "\$SYSTEM_PROMPT" "\$INPUT" | codex exec -m "\$_MODEL" -s "\$_CODEX_SANDBOX" --full-auto -
                else
                    echo "\$INPUT" | claude -p --model "\$_MODEL" --append-system-prompt "\$SYSTEM_PROMPT" --allowedTools "${allowed_tools}"
                fi
                ;;
        esac
    done
LAUNCHER
    else
        local starts_immediately
        starts_immediately=$(yq_get ".agents.$agent.auto_start // false")

        if [ "$starts_immediately" = "true" ]; then
            sed 's/^    //' > "$PROMPT_DIR/run-${agent}.sh" << LAUNCHER
    #!/bin/bash
    cd '${REPO_DIR}'
    printf '\033]0;${label}\007'
    SYSTEM_PROMPT=\$(cat '${PROMPT_DIR}/${agent}-system.txt')
    INIT_PROMPT=\$(cat '${PROMPT_DIR}/${agent}-init.txt')
    CMD_LIST_READY='${TICKET_LIST_READY}'
    TRIGGER_DIR='${PROMPT_DIR}/triggers'
    mkdir -p "\$TRIGGER_DIR"
    _PROVIDER='${provider}'
    _MODEL='${model}'
    _CODEX_SANDBOX='${codex_sandbox}'
    echo "idle \$(date +%s) starting" > "\$TRIGGER_DIR/${agent}.state"
    _collect_triggers() {
        local _collected=""
        for TRIGGER_FILE in "\$TRIGGER_DIR/${agent}.from-"*.trigger; do
            [ -f "\$TRIGGER_FILE" ] || continue
            _collected="\${_collected}\$(cat "\$TRIGGER_FILE")
"
            rm -f "\$TRIGGER_FILE"
        done
        if [ -f "\$TRIGGER_DIR/${agent}.trigger" ]; then
            _collected="\${_collected}\$(cat "\$TRIGGER_DIR/${agent}.trigger")
"
            rm -f "\$TRIGGER_DIR/${agent}.trigger"
        fi
        printf '%s' "\$_collected"
    }
    _has_ready_ticket() {
        local _ready=""
        if [ -n "\$CMD_LIST_READY" ]; then
            _ready=\$(eval "\$CMD_LIST_READY" 2>/dev/null || true)
        fi
        [ -n "\$(printf '%s' "\$_ready" | tr -d '[:space:]')" ]
    }
    _STATE_FILE='${STATE_FILE}'
    _inject_issue_context() {
        local _msg="\$1"
        if [ -z "\$_STATE_FILE" ] || [ ! -f "\$_STATE_FILE" ]; then printf '%s' "\$_msg"; return; fi
        if ! printf '%s' "\$_msg" | grep -qiE "^DONE-[a-z]"; then printf '%s' "\$_msg"; return; fi
        local _ctx
        _ctx=\$(jq -r '.current_issue // empty | "Issue #\(.id): \(.title)\nContext: \(.context)"' "\$_STATE_FILE" 2>/dev/null)
        if [ -z "\$_ctx" ]; then printf '%s' "\$_msg"; return; fi
        printf '%s\n\n---\n%s' "\$_ctx" "\$_msg"
    }
    # Provider-aware CLI invocation (interactive mode for auto_start)
    _run_agent_cli() {
        local _msg="\$1"
        if [ "\$_PROVIDER" = "codex" ]; then
            codex -m "\$_MODEL" -s "\$_CODEX_SANDBOX" -a never --no-alt-screen "\$(printf '%s\n\n---\n\n%s' "\$SYSTEM_PROMPT" "\$_msg")"
        else
            env -u ANTHROPIC_API_KEY claude --model "\$_MODEL" --append-system-prompt "\$SYSTEM_PROMPT" --allowedTools "${allowed_tools}" -n "${agent}" "\$_msg"
        fi
        return \$?
    }
    _WORK_DISPATCHED=false
    _has_active_work() {
        if [ -n "\$_STATE_FILE" ] && [ -f "\$_STATE_FILE" ] && command -v jq &>/dev/null; then
            local _active
            _active=\$(jq -r '.current_issue.status // empty' "\$_STATE_FILE" 2>/dev/null)
            [ "\$_active" = "in_progress" ] && return 0
        fi
        for _ws in "\$TRIGGER_DIR/"*.state; do
            [ -f "\$_ws" ] || continue
            case "\$_ws" in */${agent}.state) continue ;; esac
            local _st
            _st=\$(awk '{print \$1}' "\$_ws" 2>/dev/null)
            case "\$_st" in running|working|thinking) return 0 ;; esac
        done
        [ "\$_WORK_DISPATCHED" = true ] && return 0
        return 1
    }
    while true; do
        PENDING_MSG=\$(_collect_triggers)
        if [ -n "\$PENDING_MSG" ]; then
            PENDING_MSG=\$(_inject_issue_context "\$PENDING_MSG")
            echo "running \$(date +%s) \${PENDING_MSG:0:50}" > "\$TRIGGER_DIR/${agent}.state"
            _run_agent_cli "\$PENDING_MSG"
            _WORK_DISPATCHED=false
        elif _has_active_work; then
            echo "idle \$(date +%s) waiting for workers" > "\$TRIGGER_DIR/${agent}.state"
            echo "--- [\$(date '+%H:%M:%S')] Workers still active. Waiting for DONE messages... ---"
            sleep 5
            continue
        elif _has_ready_ticket; then
            echo "running \$(date +%s) initial planning" > "\$TRIGGER_DIR/${agent}.state"
            _run_agent_cli "\$INIT_PROMPT"
            _WORK_DISPATCHED=true
        else
            echo "idle \$(date +%s) waiting" > "\$TRIGGER_DIR/${agent}.state"
            echo "No ready tickets found. Waiting for the PM to send one."
            sleep 2
            continue
        fi
        if [ "\$?" -ne 0 ]; then
            echo "retrying \$(date +%s) session restart in 5s" > "\$TRIGGER_DIR/${agent}.state"
            echo "--- [\$(date '+%H:%M:%S')] Session ended with error. Retrying in 5s... ---"
            sleep 5
        else
            echo "idle \$(date +%s) waiting" > "\$TRIGGER_DIR/${agent}.state"
        fi
        COMPLETE_MARKER="\$TRIGGER_DIR/.work-done"
        if [ -f "\$COMPLETE_MARKER" ]; then
            '${PROMPT_DIR}/send-to-agent.sh' PM "COMPLETE: All tasks finished (auto-notify)"
            rm -f "\$COMPLETE_MARKER"
            _WORK_DISPATCHED=false
        fi
    done
LAUNCHER
        else
            sed 's/^    //' > "$PROMPT_DIR/run-${agent}.sh" << LAUNCHER
    #!/bin/bash
    cd '${REPO_DIR}'
    printf '\033]0;${label}\007'
    SYSTEM_PROMPT=\$(cat '${PROMPT_DIR}/${agent}-system.txt')
    TRIGGER_DIR='${PROMPT_DIR}/triggers'
    mkdir -p "\$TRIGGER_DIR"
    _PROVIDER='${provider}'
    _MODEL='${model}'
    _CODEX_SANDBOX='${codex_sandbox}'
    echo "idle \$(date +%s)" > "\$TRIGGER_DIR/${agent}.state"
    _collect_worker_triggers() {
        local _work="\$TRIGGER_DIR/${agent}.msg"
        local _found=false
        : > "\$_work"
        for _tf in "\$TRIGGER_DIR/${agent}.from-"*.trigger; do
            [ -f "\$_tf" ] || continue
            cat "\$_tf" >> "\$_work"
            printf '\n' >> "\$_work"
            rm -f "\$_tf"
            _found=true
        done
        if [ -f "\$TRIGGER_DIR/${agent}.trigger" ]; then
            cat "\$TRIGGER_DIR/${agent}.trigger" >> "\$_work"
            printf '\n' >> "\$_work"
            rm -f "\$TRIGGER_DIR/${agent}.trigger"
            _found=true
        fi
        if [ "\$_found" = true ] && [ -s "\$_work" ]; then
            return 0
        fi
        rm -f "\$_work"
        return 1
    }
    # Event-driven loop: wait for trigger files, start Claude with their contents
    while true; do
        if _collect_worker_triggers; then
            WORK_FILE="\$TRIGGER_DIR/${agent}.msg"
            printf '%s\n' "ACK \$(date '+%H:%M:%S')" > "\$TRIGGER_DIR/${agent}.ack"
            if [ -s "\$WORK_FILE" ]; then
                TASK_PREVIEW=\$(head -c 50 "\$WORK_FILE")
                echo "working \$(date +%s) \$TASK_PREVIEW" > "\$TRIGGER_DIR/${agent}.state"
                rm -f "\$TRIGGER_DIR/${agent}.done-sent"
                if [ "\$_PROVIDER" = "codex" ]; then
                    printf '%s\n\n---\n\n%s' "\$SYSTEM_PROMPT" "\$(cat "\$WORK_FILE")" | codex exec -m "\$_MODEL" -s "\$_CODEX_SANDBOX" --full-auto -
                else
                    cat "\$WORK_FILE" | claude -p --model "\$_MODEL" --append-system-prompt "\$SYSTEM_PROMPT" --allowedTools "${allowed_tools}" -n "${agent}"
                fi
                if [ ! -f "\$TRIGGER_DIR/${agent}.done-sent" ]; then
                    '${PROMPT_DIR}/send-to-agent.sh' '${auto_start_label}' "DONE-${agent}: Task completed (auto-notify)"
                fi
                rm -f "\$TRIGGER_DIR/${agent}.done-sent"
                echo "idle \$(date +%s)" > "\$TRIGGER_DIR/${agent}.state"
            fi
            rm -f "\$WORK_FILE"
        else
            sleep 1
        fi
    done
LAUNCHER
        fi
    fi
    chmod +x "$PROMPT_DIR/run-${agent}.sh"
}

# ── Generate All ──
generate_send_to_agent

for agent in "${AGENTS[@]}"; do
    generate_system_prompt "$agent"
    generate_init_prompt "$agent"
    generate_launcher "$agent"
done

echo "Generated prompts and launchers for: ${AGENTS[*]}"
