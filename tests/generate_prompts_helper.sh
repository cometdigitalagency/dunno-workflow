#!/bin/bash
# generate_prompts_helper.sh — runs prompt generation without launching iTerm2

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
normalize_provider() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

PROJECT_NAME=$(yq_get '.project.name')
REPO_NAME=$(yq_get '.project.repo // ""')
TICKET_SOURCE=$(yq_get '.tickets.source')
FILE_TICKET_DIR=$(yq_get '.tickets.file.directory // "./tickets"')
WORKFLOW_PROVIDER=$(normalize_provider "$(yq_get '.runtime.provider // "claude"')")
[ -z "$WORKFLOW_PROVIDER" ] && WORKFLOW_PROVIDER="claude"

AGENTS=()
while IFS= read -r agent; do
    AGENTS+=("$agent")
done < <(yq_get '.agents | keys | .[]')

PROMPT_DIR="${WORK_DIR}/.team-prompts"
mkdir -p "$PROMPT_DIR"

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

    rules_count=$(yq_get ".agents.$agent.rules | length")
    if [ "$rules_count" != "0" ]; then
        prompt+="## RULES\n"
        while IFS= read -r rule; do
            prompt+="- ${rule}\n"
        done < <(yq_get ".agents.$agent.rules[]")
        prompt+="\n"
    fi

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

get_agent_provider() {
    local agent="$1"
    local provider
    provider=$(normalize_provider "$(yq_get ".agents.$agent.provider // \"${WORKFLOW_PROVIDER}\"")")
    [ -z "$provider" ] && provider="$WORKFLOW_PROVIDER"
    echo "$provider"
}

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
HELPER
    chmod +x "$PROMPT_DIR/send-to-agent.sh"
}

generate_launcher() {
    local agent="$1"
    local interactive provider model
    interactive=$(yq_get ".agents.$agent.interactive")
    provider=$(get_agent_provider "$agent")
    model=$(yq_get ".agents.$agent.model // \"\"")
    label=$(echo "$agent" | tr '[:lower:]' '[:upper:]')
    allowed_tools=$(get_allowed_tools "$agent")

    auto_start_agent=""
    auto_start_label=""
    for _a in "${AGENTS[@]}"; do
        if [ "$(yq_get ".agents.$_a.auto_start // false")" = "true" ]; then
            auto_start_agent="$_a"
            auto_start_label=$(echo "$_a" | tr '[:lower:]' '[:upper:]')
            break
        fi
    done

    if [ "$interactive" = "true" ]; then
        local _agent_list=""
        for _a in "${AGENTS[@]}"; do
            [ "$_a" != "$agent" ] && _agent_list+="$_a "
        done
        _agent_list="${_agent_list% }"

        sed 's/^    //' > "$PROMPT_DIR/run-${agent}.sh" << LAUNCHER
    #!/bin/bash
    cd '${WORK_DIR}'
    PROVIDER='${provider}'
    MODEL='${model}'
    AGENT_NAME='${agent}'
    REPO_DIR='${WORK_DIR}'
    ALLOWED_TOOLS='${allowed_tools}'
    SYSTEM_PROMPT=\$(cat '${PROMPT_DIR}/${agent}-system.txt')
    TRIGGER_DIR='${PROMPT_DIR}/triggers'
    TICKET_SOURCE_KIND='${TICKET_SOURCE}'
    FILE_TICKET_DIR='${FILE_TICKET_DIR}'
    AGENT_LIST="${_agent_list}"
    CMD_LIST_OPEN="${TICKET_LIST_OPEN}"
    CMD_LIST_READY="${TICKET_LIST_READY}"
    CMD_VIEW="${TICKET_VIEW}"
    CMD_CLAIM="${TICKET_CLAIM}"
    CMD_COMMENT="${TICKET_COMMENT}"
    CMD_CLOSE="${TICKET_CLOSE}"
    CMD_CREATE="${TICKET_CREATE}"
    CMD_LIST_STALE="${TICKET_LIST_STALE}"

    _provider_exec_prompt() {
        local _prompt="\$1"
        if [ "\$PROVIDER" = "claude" ]; then
            echo "\$_prompt" | claude -p --append-system-prompt "\$SYSTEM_PROMPT" --allowedTools "\$ALLOWED_TOOLS"
        else
            printf '%s\n\n%s\n' "\$SYSTEM_PROMPT" "\$_prompt" | codex exec --sandbox workspace-write -C "\$REPO_DIR" -
        fi
    }

    _ticket_meta() {
        awk '
            BEGIN { in_frontmatter=0; id=""; title=""; status="" }
            \$0 == "---" {
                if (in_frontmatter == 0) { in_frontmatter=1; next }
                exit
            }
            in_frontmatter && /^id:[[:space:]]*/ { line=\$0; sub(/^id:[[:space:]]*/, "", line); sub(/[[:space:]]*#.*/, "", line); id=line }
            in_frontmatter && /^title:[[:space:]]*/ { line=\$0; sub(/^title:[[:space:]]*/, "", line); sub(/[[:space:]]*#.*/, "", line); title=line }
            in_frontmatter && /^status:[[:space:]]*/ { line=\$0; sub(/^status:[[:space:]]*/, "", line); sub(/[[:space:]]*#.*/, "", line); status=line }
            END { printf "%s|%s|%s\n", id, title, status }
        ' "\$1"
    }

    _resolve_ticket_ref() {
        local _ref="\$1"
        [ "\$TICKET_SOURCE_KIND" != "file" ] && { printf '%s\n' "\$_ref"; return 0; }
        [ -f "\$_ref" ] && { printf '%s\n' "\$_ref"; return 0; }
        local _f _meta _id
        for _f in "\$FILE_TICKET_DIR"/*.md; do
            [ -f "\$_f" ] || continue
            _meta=\$(_ticket_meta "\$_f")
            _id=\$(printf '%s' "\$_meta" | cut -d'|' -f1)
            [ "\$_id" = "\$_ref" ] && { printf '%s\n' "\$_f"; return 0; }
        done
        return 1
    }

    _list_file_tickets() {
        local _mode="\$1"
        local _count=0 _f _meta _id _title _status
        for _f in "\$FILE_TICKET_DIR"/*.md; do
            [ -f "\$_f" ] || continue
            _meta=\$(_ticket_meta "\$_f")
            _id=\$(printf '%s' "\$_meta" | cut -d'|' -f1)
            _title=\$(printf '%s' "\$_meta" | cut -d'|' -f2)
            _status=\$(printf '%s' "\$_meta" | cut -d'|' -f3)
            case "\$_mode" in
                open) [ "\$_status" = "ready" ] || [ "\$_status" = "in-progress" ] || continue ;;
                ready) [ "\$_status" = "ready" ] || continue ;;
                stale) [ "\$_status" = "in-progress" ] || continue ;;
                *) continue ;;
            esac
            printf "  #%s [%s] %s\n" "\$_id" "\$_status" "\$_title"
            _count=\$((_count + 1))
        done
        [ "\$_count" -gt 0 ] || echo "  (no tickets found)"
    }

    _drain_pm_messages() {
        _PM_MSG=""
        for _tf in "\$TRIGGER_DIR/${agent}.from-"*.trigger; do
            [ -f "\$_tf" ] || continue
            _PM_MSG="\${_PM_MSG}\$(cat "\$_tf")
"
            rm -f "\$_tf"
        done
        if [ -f "\$TRIGGER_DIR/${agent}.trigger" ]; then
            _PM_MSG="\${_PM_MSG}\$(cat "\$TRIGGER_DIR/${agent}.trigger")
"
            rm -f "\$TRIGGER_DIR/${agent}.trigger"
        fi
        if [ -n "\$_PM_MSG" ]; then
            printf '%s\n' "ACK \$(date '+%H:%M:%S')" > "\$TRIGGER_DIR/${agent}.ack"
            echo "\$_PM_MSG"
        fi
    }

    while true; do
        _drain_pm_messages
        read -r -p "PM> " INPUT || break
        [ -z "\$INPUT" ] && continue
        case "\$INPUT" in
            help)
                echo "  status | backlog | view N | close N | claim N | tell agent msg | agents | /bash cmd | ai prompt | quit"
                ;;
            status)
                if [ "\$TICKET_SOURCE_KIND" = "file" ]; then
                    _list_file_tickets open
                else
                    eval "\$CMD_LIST_OPEN" 2>/dev/null || echo "(no tickets)"
                fi
                ;;
            backlog|"show backlog")
                if [ "\$TICKET_SOURCE_KIND" = "file" ]; then
                    _list_file_tickets ready
                else
                    eval "\$CMD_LIST_READY" 2>/dev/null || echo "(no tickets)"
                fi
                ;;
            stale)
                if [ "\$TICKET_SOURCE_KIND" = "file" ]; then
                    _list_file_tickets stale
                fi
                ;;
            view\ *|issue\ *)
                N=\$(echo "\$INPUT" | sed 's/^[a-z]* #*//' | tr -d ' ')
                if [ "\$TICKET_SOURCE_KIND" = "file" ]; then
                    TICKET_FILE=\$(_resolve_ticket_ref "\$N") || { echo "ERROR: could not view ticket \$N"; continue; }
                    cat "\$TICKET_FILE"
                fi
                ;;
            close\ *|"close issue"\ *)
                N=\$(echo "\$INPUT" | sed 's/^close *issue *#*//' | sed 's/^close *//' | tr -d ' ')
                if [ "\$TICKET_SOURCE_KIND" = "file" ]; then
                    TICKET_FILE=\$(_resolve_ticket_ref "\$N") || { echo "ERROR: could not close ticket \$N"; continue; }
                    sed -i '' 's/^status: in-progress/status: done/' "\$TICKET_FILE" && echo "Done."
                fi
                ;;
            claim\ *)
                N=\$(echo "\$INPUT" | sed 's/^claim *#*//' | tr -d ' ')
                if [ "\$TICKET_SOURCE_KIND" = "file" ]; then
                    TICKET_FILE=\$(_resolve_ticket_ref "\$N") || { echo "ERROR: could not claim ticket \$N"; continue; }
                    sed -i '' 's/^status: ready/status: in-progress/' "\$TICKET_FILE" && echo "Done."
                fi
                ;;
            comment\ *)
                N=\$(echo "\$INPUT" | awk '{print \$2}' | tr -d '#')
                MSG=\$(echo "\$INPUT" | sed 's/^comment *[#0-9]* *//')
                if [ "\$TICKET_SOURCE_KIND" = "file" ]; then
                    TICKET_FILE=\$(_resolve_ticket_ref "\$N") || { echo "ERROR: could not comment on ticket \$N"; continue; }
                    printf '\n---\n### %s\n%s\n' "\$MSG" "\$(date)" >> "\$TICKET_FILE" && echo "Comment added."
                fi
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
                    '${PROMPT_DIR}/send-to-agent.sh' "\$AGENT_UPPER" "\$MSG"
                fi
                ;;
            /bash\ *)
                CMD_RAW=\$(echo "\$INPUT" | sed 's#^/bash *##')
                [ -z "\$CMD_RAW" ] && echo "ERROR: /bash requires a command" && continue
                case "\$CMD_RAW" in
                    status|backlog|stale|agents|team|view*|issue*|close*|claim*|comment*|tell*|ai*)
                        echo "ERROR: '\$CMD_RAW' is a PM command. Run it without /bash."
                        continue
                        ;;
                esac
                eval "\$CMD_RAW"
                ;;
            ai\ *)
                PROMPT=\$(echo "\$INPUT" | sed 's/^ai *//')
                _provider_exec_prompt "\$PROMPT"
                ;;
            quit|exit) break ;;
            *) _provider_exec_prompt "\$INPUT" ;;
        esac
    done
LAUNCHER
    else
        starts_immediately=$(yq_get ".agents.$agent.auto_start // false")
        if [ "$starts_immediately" = "true" ]; then
            sed 's/^    //' > "$PROMPT_DIR/run-${agent}.sh" << LAUNCHER
    #!/bin/bash
    cd '${WORK_DIR}'
    PROVIDER='${provider}'
    MODEL='${model}'
    AGENT_NAME='${agent}'
    REPO_DIR='${WORK_DIR}'
    ALLOWED_TOOLS='${allowed_tools}'
    SYSTEM_PROMPT=\$(cat '${PROMPT_DIR}/${agent}-system.txt')
    INIT_PROMPT=\$(cat '${PROMPT_DIR}/${agent}-init.txt')
    TRIGGER_DIR='${PROMPT_DIR}/triggers'
    echo "idle \$(date +%s)" > "\$TRIGGER_DIR/${agent}.state"

    _provider_run_prompt() {
        local _prompt="\$1"
        if [ "\$PROVIDER" = "claude" ]; then
            claude --append-system-prompt "\$SYSTEM_PROMPT" --allowedTools "\$ALLOWED_TOOLS" -n "\$AGENT_NAME" "\$_prompt"
        else
            printf '%s\n\n%s\n' "\$SYSTEM_PROMPT" "\$_prompt" | codex exec --sandbox workspace-write -C "\$REPO_DIR" -
        fi
    }

    _collect_triggers() {
        local _collected=""
        for _tf in "\$TRIGGER_DIR/${agent}.from-"*.trigger; do
            [ -f "\$_tf" ] || continue
            _collected="\${_collected}\$(cat "\$_tf")
"
            rm -f "\$_tf"
        done
        if [ -f "\$TRIGGER_DIR/${agent}.trigger" ]; then
            _collected="\${_collected}\$(cat "\$TRIGGER_DIR/${agent}.trigger")
"
            rm -f "\$TRIGGER_DIR/${agent}.trigger"
        fi
        printf '%s' "\$_collected"
    }

    while true; do
        PENDING_MSG=\$(_collect_triggers)
        if [ -n "\$PENDING_MSG" ]; then
            echo "working \$(date +%s) \${PENDING_MSG:0:50}" > "\$TRIGGER_DIR/${agent}.state"
            _provider_run_prompt "\$PENDING_MSG"
        else
            echo "working \$(date +%s)" > "\$TRIGGER_DIR/${agent}.state"
            _provider_run_prompt "\$INIT_PROMPT"
        fi
        echo "idle \$(date +%s)" > "\$TRIGGER_DIR/${agent}.state"
        COMPLETE_MARKER="\$TRIGGER_DIR/.work-done"
        if [ -f "\$COMPLETE_MARKER" ]; then
            '${PROMPT_DIR}/send-to-agent.sh' PM "COMPLETE: All tasks finished (auto-notify)"
            rm -f "\$COMPLETE_MARKER"
        fi
        sleep 5
    done
LAUNCHER
        else
            sed 's/^    //' > "$PROMPT_DIR/run-${agent}.sh" << LAUNCHER
    #!/bin/bash
    cd '${WORK_DIR}'
    PROVIDER='${provider}'
    MODEL='${model}'
    AGENT_NAME='${agent}'
    REPO_DIR='${WORK_DIR}'
    ALLOWED_TOOLS='${allowed_tools}'
    SYSTEM_PROMPT=\$(cat '${PROMPT_DIR}/${agent}-system.txt')
    TRIGGER_DIR='${PROMPT_DIR}/triggers'
    echo "idle \$(date +%s)" > "\$TRIGGER_DIR/${agent}.state"

    _provider_run_file() {
        local _file="\$1"
        if [ "\$PROVIDER" = "claude" ]; then
            cat "\$_file" | claude -p --append-system-prompt "\$SYSTEM_PROMPT" --allowedTools "\$ALLOWED_TOOLS" -n "\$AGENT_NAME"
        else
            { printf '%s\n\n' "\$SYSTEM_PROMPT"; cat "\$_file"; } | codex exec --sandbox workspace-write -C "\$REPO_DIR" -
        fi
    }

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

    # Event-driven loop: wait for trigger files, start provider with their contents
    while true; do
        if _collect_worker_triggers; then
            WORK_FILE="\$TRIGGER_DIR/${agent}.msg"
            printf '%s\n' "ACK \$(date '+%H:%M:%S')" > "\$TRIGGER_DIR/${agent}.ack"
            if [ -s "\$WORK_FILE" ]; then
                TASK_PREVIEW=\$(head -c 50 "\$WORK_FILE")
                echo "working \$(date +%s) \$TASK_PREVIEW" > "\$TRIGGER_DIR/${agent}.state"
                rm -f "\$TRIGGER_DIR/${agent}.done-sent"
                _provider_run_file "\$WORK_FILE"
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

generate_send_to_agent

for agent in "${AGENTS[@]}"; do
    generate_system_prompt "$agent"
    generate_init_prompt "$agent"
    generate_launcher "$agent"
done

echo "Generated prompts and launchers for: ${AGENTS[*]}"
