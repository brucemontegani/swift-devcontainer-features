#!/usr/bin/env bash
set -e
set -x

# The 'install.sh' entrypoint script is always executed as the root user.
#
# These following environment variables are passed in by the dev container CLI.
# These may be useful in instances where the context of the final
# remoteUser or containerUser is useful.
# For more details, see https://containers.dev/implementors/features#user-env-var
# echo "The effective dev container remoteUser is '$_REMOTE_USER'"
# echo "The effective dev container remoteUser's home directory is '$_REMOTE_USER_HOME'"

# echo "The effective dev container containerUser is '$_CONTAINER_USER'"
# echo "The effective dev container containerUser's home directory is '$_CONTAINER_USER_HOME'"

STARTDIR=$(pwd)
TEMPDIR=$(mktemp -d)
VERSION=${VERSION:-"default"}

cleanup()
{
    local exit_status=$?
    echo "Cleaning up... Exit status: $exit_status"
    cd "$STARTDIR"
    if [ -n "$TEMPDIR" ]; then
        rm -rf "$TEMPDIR"
    fi
}

# Gets the swift-format version from a swift version
# Arguments:
#   None
# Outputs:
#   swift-format version.
#       For swift versions 5.8 and higher -> 508.x.x, 509.x.x, etc
#       For swift versions 5.7 and lower  -> 0.50700.x, 0.50600.x, etc
get_swift_format_version() {
    local swift_version=$(swift --version | egrep -o 'Swift version [0-9]+.[0-9]+' | tail -c +15)

    local major_version
    local minor_version

    # Parse the swift version into major and minor parts
    IFS='.' read -r maj_version minor_version <<< "$swift_version"

    # minor version must be two digits
    if [ ${#minor_version} -eq 1 ]; then
        minor_version="0${minor_version}"
    fi

    # Create the swift-format version
    local swift_format_version="${maj_version}${minor_version}"

    # Convert to a number (integer)
    version_as_number=$((10#$swift_format_version))

    local swift_format_version_filter
    # Swift version LT 508, version filter format is 0.xxx00.* format where xxx is major version
    if [[ "$version_as_number" -lt 508 ]]; then
        swift_format_version_filter="0.${swift_format_version}00.*"
    else
        # Swift version GE 508, version filter format is xxx.*.* format where xxx is major version
        swift_format_version_filter="${swift_format_version}.*.*"
    fi

   # From git tags, get the last swift-format version for the major version using the version filter
    VERSION=$(git tag -l "$swift_format_version_filter" | tail -n 1)

    echo "$VERSION"
}

trap cleanup EXIT

echo "Downloading swiftlang/swift-format"
git clone https://github.com/swiftlang/swift-format "$TEMPDIR"
cd "$TEMPDIR"

# Set the swift-format version
if [[ "$VERSION" == "default" ]]; then
    VERSION=$(get_swift_format_version)
    # if no version is found (which could happen if a version has not been released yet (e.g. swift 6.0)) then the main branch will be used.
    if [[ -z "$VERSION" ]]; then
        VERSION="main"
    fi
elif [[ "$VERSION" == "development" ]]; then
    VERSION="main"
fi

echo "Checking out swift-format version from git repo"

set +e

git checkout "$VERSION"

command_output=$(git checkout "$VERSION" 2>&1)
command_status=$?
if [ $command_status -ne 0 ]; then
    echo "ERROR: git checkout command failed with the following error:"
    echo "$command_output"
    exit 1
fi
set -e

echo "Building swift-format version-> ${VERSION}"
swift build -c release --product swift-format

echo "Movin swift-format to /usr/local/bin"
swift_format=$(swift build -c release --show-bin-path)/swift-format
cp "$swift_format" /usr/local/bin

echo "swift-format successfully installed"
