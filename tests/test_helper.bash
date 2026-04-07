# test_helper.bash — shared setup for all bats tests

DUNNO_WORKFLOW="$(cd "$(dirname "$BATS_TEST_FILENAME")/../bin" && pwd)/dunno-workflow"
FIXTURES_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/fixtures" && pwd)"

# Create a temporary working directory for each test
setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    export TEST_WORK_DIR
}

# Clean up after each test
teardown() {
    rm -rf "$TEST_WORK_DIR"
}

# Run dunno-workflow from a specific directory
run_in_dir() {
    local dir="$1"
    shift
    (cd "$dir" && "$DUNNO_WORKFLOW" "$@")
}

# Copy a fixture into the test working directory as workflow.yaml
use_fixture() {
    cp "$FIXTURES_DIR/$1" "$TEST_WORK_DIR/workflow.yaml"
}
