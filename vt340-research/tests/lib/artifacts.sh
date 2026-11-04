#!/bin/sh

# Copy a test's internal evidence into the common runner's artifact directory.
# Direct invocation remains unchanged when VT340_TEST_ARTIFACT_DIR is unset.
vt340_artifact_copy()
{
	source_path=$1
	artifact_name=$2
	if test -n "${VT340_TEST_ARTIFACT_DIR:-}" && test -e "$source_path"; then
		mkdir -p "$VT340_TEST_ARTIFACT_DIR"
		cp "$source_path" "$VT340_TEST_ARTIFACT_DIR/$artifact_name"
	fi
}

vt340_artifact_path()
{
	default_path=$1
	artifact_name=$2
	if test -n "${VT340_TEST_ARTIFACT_DIR:-}"; then
		mkdir -p "$VT340_TEST_ARTIFACT_DIR"
		printf '%s/%s\n' "$VT340_TEST_ARTIFACT_DIR" "$artifact_name"
	else
		printf '%s\n' "$default_path"
	fi
}
