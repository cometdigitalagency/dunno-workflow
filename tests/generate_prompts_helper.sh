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

# ── Generate All ──
for agent in "${AGENTS[@]}"; do
    generate_system_prompt "$agent"
    generate_init_prompt "$agent"
done

echo "Generated prompts for: ${AGENTS[*]}"
