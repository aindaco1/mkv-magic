#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
    echo "usage: $0 <absolute-prior-app> <absolute-candidate-zip> <vMAJOR.MINOR.PATCH> <absolute-private-key-file> <require-distribution:0|1>" >&2
    exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
prior_app_input="$1"
candidate_zip_input="$2"
release_tag="$3"
private_key_input="$4"
require_distribution="$5"
"$repo_root/scripts/release/validate-tag-format.sh" "$release_tag"
version="${release_tag#v}"

case "$require_distribution" in
    0|1) ;;
    *) echo "require-distribution must be 0 or 1" >&2; exit 64 ;;
esac
if [[ "$prior_app_input" != /* || ! -d "$prior_app_input" || -L "$prior_app_input" || \
      "${prior_app_input##*/}" != "MKV Magic.app" ]]; then
    echo "prior MKV Magic app is missing or unsafe" >&2
    exit 1
fi
expected_zip_name="MKV-Magic-$version-universal.zip"
if [[ "$candidate_zip_input" != /* || ! -f "$candidate_zip_input" || \
      -L "$candidate_zip_input" || ! -s "$candidate_zip_input" || \
      "${candidate_zip_input##*/}" != "$expected_zip_name" ]]; then
    echo "candidate update archive is missing or unsafe" >&2
    exit 1
fi
if [[ "$private_key_input" != /* || ! -f "$private_key_input" || \
      -L "$private_key_input" || ! -s "$private_key_input" ]]; then
    echo "Sparkle private key file is missing or unsafe" >&2
    exit 1
fi
validate_private_key_file() {
    local key_file="$1"
    local permissions
    local bytes
    permissions="$(stat -f '%Lp' "$key_file")"
    bytes="$(stat -f '%z' "$key_file")"
    if [[ "$permissions" != 400 && "$permissions" != 600 ]] || \
        [[ "$bytes" -ne 44 && "$bytes" -ne 45 ]] || \
        ! grep -Eq '^[A-Za-z0-9+/]{43}=$' "$key_file"; then
        echo "Sparkle private key file must contain one owner-only Ed25519 key" >&2
        exit 1
    fi
}
validate_private_key_file "$private_key_input"
if [[ -n "${MKV_MAGIC_EXPECTED_APPCAST_PATH:-}" && \
      ( "$MKV_MAGIC_EXPECTED_APPCAST_PATH" != /* || \
        ! -f "$MKV_MAGIC_EXPECTED_APPCAST_PATH" || \
        -L "$MKV_MAGIC_EXPECTED_APPCAST_PATH" || \
        ! -s "$MKV_MAGIC_EXPECTED_APPCAST_PATH" ) ]]; then
    echo "expected appcast is missing or unsafe" >&2
    exit 1
fi
if [[ -n "${MKV_MAGIC_REJECTION_PRIVATE_KEY_FILE:-}" && \
      ( "$MKV_MAGIC_REJECTION_PRIVATE_KEY_FILE" != /* || \
        ! -f "$MKV_MAGIC_REJECTION_PRIVATE_KEY_FILE" || \
        -L "$MKV_MAGIC_REJECTION_PRIVATE_KEY_FILE" || \
        ! -s "$MKV_MAGIC_REJECTION_PRIVATE_KEY_FILE" ) ]]; then
    echo "rejection-test private key is missing or unsafe" >&2
    exit 1
fi
if [[ -n "${MKV_MAGIC_REJECTION_PRIVATE_KEY_FILE:-}" ]]; then
    validate_private_key_file "$MKV_MAGIC_REJECTION_PRIVATE_KEY_FILE"
fi
if [[ "$require_distribution" == 1 && \
      -z "${MKV_MAGIC_EXPECTED_APPCAST_PATH:-}" ]]; then
    echo "distribution acceptance requires the downloaded draft appcast" >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required for the loopback-only updater acceptance server" >&2
    exit 1
fi

prior_app="$(cd "$(dirname "$prior_app_input")" && pwd -P)/$(basename "$prior_app_input")"
candidate_zip="$(cd "$(dirname "$candidate_zip_input")" && pwd -P)/$(basename "$candidate_zip_input")"
private_key_file="$(cd "$(dirname "$private_key_input")" && pwd -P)/$(basename "$private_key_input")"
work_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-update-replacement.XXXXXX")"
server_pid=''
cleanup() {
    if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    /bin/rm -rf -- "$work_root"
}
trap cleanup EXIT

working_app="$work_root/prior/MKV Magic.app"
candidate_extract="$work_root/candidate"
feed_root="$work_root/feed"
cli_build_root="$work_root/sparkle-cli"
mkdir -p "$(dirname "$working_app")" "$candidate_extract" "$feed_root"
ditto --norsrc --noextattr "$prior_app" "$working_app"

unsafe_zip_entry=0
zip_entry_count=0
while IFS= read -r zip_entry; do
    zip_entry_count=$((zip_entry_count + 1))
    case "$zip_entry" in
        /*|../*|*/../*|*/..|*\\*) unsafe_zip_entry=1 ;;
    esac
done < <(unzip -Z1 "$candidate_zip")
if [[ "$zip_entry_count" -eq 0 || "$unsafe_zip_entry" -ne 0 ]]; then
    echo "candidate update archive contains an unsafe path" >&2
    exit 1
fi
ditto -x -k --noextattr "$candidate_zip" "$candidate_extract"
candidate_app="$candidate_extract/MKV Magic.app"
if [[ ! -d "$candidate_app" || -L "$candidate_app" ]] || \
    find "$candidate_extract" -mindepth 1 -maxdepth 1 ! -name 'MKV Magic.app' \
        -print -quit | grep -q .; then
    echo "candidate update archive layout is unsafe" >&2
    exit 1
fi

plist_value() {
    plutil -extract "$1" raw -o - "$2/Contents/Info.plist"
}
prior_version="$(plist_value CFBundleShortVersionString "$working_app")"
prior_build="$(plist_value CFBundleVersion "$working_app")"
candidate_version="$(plist_value CFBundleShortVersionString "$candidate_app")"
candidate_build="$(plist_value CFBundleVersion "$candidate_app")"
prior_identifier="$(plist_value CFBundleIdentifier "$working_app")"
candidate_identifier="$(plist_value CFBundleIdentifier "$candidate_app")"
prior_public_key="$(plist_value SUPublicEDKey "$working_app")"
candidate_public_key="$(plist_value SUPublicEDKey "$candidate_app")"
candidate_feed="$(plist_value SUFeedURL "$candidate_app")"

if [[ "$candidate_version" != "$version" || \
      ! "$prior_build" =~ ^[1-9][0-9]*$ || \
      ! "$candidate_build" =~ ^[1-9][0-9]*$ || \
      "$candidate_build" -le "$prior_build" || \
      "$prior_identifier" != "$candidate_identifier" || \
      "$prior_public_key" != "$candidate_public_key" || \
      ! "$candidate_public_key" =~ ^[A-Za-z0-9+/]{43}=$ || \
      "$candidate_feed" != "https://github.com/aindaco1/mkv-magic/releases/latest/download/appcast.xml" ]]; then
    echo "prior app and candidate do not satisfy the updater acceptance contract" >&2
    exit 1
fi
case "$require_distribution:$candidate_identifier" in
    1:com.dustwave.mkvmagic|0:com.dustwave.mkvmagic.package-gate) ;;
    *) echo "candidate bundle identifier does not match the acceptance mode" >&2; exit 1 ;;
esac

codesign --verify --deep --strict --verbose=2 "$working_app"
codesign --verify --deep --strict --verbose=2 "$candidate_app"
if [[ "$require_distribution" == 1 ]]; then
    xcrun stapler validate "$working_app"
    xcrun stapler validate "$candidate_app"
    spctl --assess --type execute --verbose=2 "$working_app"
    spctl --assess --type execute --verbose=2 "$candidate_app"
fi

sparkle_checkout="$repo_root/.build/checkouts/Sparkle"
sparkle_revision="$(jq -r '.pins[] | select(.identity == "sparkle") | .state.revision' "$repo_root/Package.resolved")"
sparkle_version="$(jq -r '.pins[] | select(.identity == "sparkle") | .state.version' "$repo_root/Package.resolved")"
if [[ ! "$sparkle_revision" =~ ^[0-9a-f]{40}$ || "$sparkle_version" != 2.9.5 || \
      ! -d "$sparkle_checkout/.git" || \
      "$(git -C "$sparkle_checkout" rev-parse HEAD)" != "$sparkle_revision" ]]; then
    echo "pinned Sparkle checkout is unavailable or inconsistent" >&2
    exit 1
fi
xcodebuild \
    -project "$sparkle_checkout/Sparkle.xcodeproj" \
    -scheme sparkle-cli \
    -configuration Release \
    -derivedDataPath "$cli_build_root" \
    CODE_SIGNING_ALLOWED=NO \
    build >"$work_root/sparkle-cli-build.log"
sparkle_cli_app="$cli_build_root/Build/Products/Release/sparkle.app"
sparkle_cli="$sparkle_cli_app/Contents/MacOS/sparkle"
if [[ ! -x "$sparkle_cli" || -L "$sparkle_cli" || \
      "$(plist_value CFBundleShortVersionString "$sparkle_cli_app")" != "$sparkle_version" ]]; then
    echo "pinned Sparkle updater driver did not build as expected" >&2
    exit 1
fi
cli_architectures="$(lipo -archs "$sparkle_cli")"
if [[ "$cli_architectures" != "x86_64 arm64" && \
      "$cli_architectures" != "arm64 x86_64" ]]; then
    echo "pinned Sparkle updater driver is not Universal" >&2
    exit 1
fi

server_log="$work_root/loopback-server.log"
python3 -u -m http.server 0 --bind 127.0.0.1 --directory "$feed_root" \
    >"$server_log" 2>&1 &
server_pid=$!
server_port=''
for ((attempt = 0; attempt < 100; attempt++)); do
    if ! kill -0 "$server_pid" 2>/dev/null; then
        echo "loopback-only updater acceptance server stopped unexpectedly" >&2
        exit 1
    fi
    server_port="$(sed -nE 's/.* port ([0-9]+) .*/\1/p' "$server_log" | head -n 1)"
    if [[ "$server_port" =~ ^[1-9][0-9]*$ ]]; then
        break
    fi
    sleep 0.05
done
if [[ ! "$server_port" =~ ^[1-9][0-9]*$ || "$server_port" -gt 65535 ]]; then
    echo "loopback-only updater acceptance server did not become ready" >&2
    exit 1
fi
feed_url="http://127.0.0.1:$server_port/appcast.xml"
download_prefix="http://127.0.0.1:$server_port/"
install -m 0644 "$candidate_zip" "$feed_root/$expected_zip_name"

generate_appcast() {
    local signing_key="$1"
    local output="$feed_root/appcast.xml"
    if [[ -e "$output" ]]; then
        /bin/rm -f -- "$output"
    fi
    "$repo_root/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" \
        --ed-key-file "$signing_key" \
        --download-url-prefix "$download_prefix" \
        --maximum-deltas 0 \
        -o "$output" "$feed_root" >/dev/null
}

extract_archive_signature() {
    python3 - "$1" "$version" <<'PY'
import sys
import xml.etree.ElementTree as ET

path, version = sys.argv[1:]
sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
root = ET.parse(path).getroot()
matches = []
for item in root.findall("./channel/item"):
    short_version = item.find(f"{{{sparkle}}}shortVersionString")
    enclosure = item.find("enclosure")
    if (
        short_version is not None
        and short_version.text == version
        and enclosure is not None
    ):
        signature = enclosure.get(f"{{{sparkle}}}edSignature")
        if signature:
            matches.append(signature)
if len(matches) != 1:
    raise SystemExit("appcast must contain exactly one matching signed archive")
print(matches[0])
PY
}

if [[ -n "${MKV_MAGIC_REJECTION_PRIVATE_KEY_FILE:-}" ]]; then
    rejection_app="$work_root/rejection/MKV Magic.app"
    mkdir -p "$(dirname "$rejection_app")"
    ditto --norsrc --noextattr "$working_app" "$rejection_app"
    generate_appcast "$MKV_MAGIC_REJECTION_PRIVATE_KEY_FILE"
    if "$sparkle_cli" "$rejection_app" \
        --check-immediately \
        --feed-url "$feed_url" \
        --user-agent-name "MKV Magic update acceptance" \
        >"$work_root/rejection.log" 2>&1; then
        echo "Sparkle accepted an update signed by the wrong key" >&2
        exit 1
    fi
    if ! grep -Eiq 'signed|signature|validat' "$work_root/rejection.log"; then
        echo "wrong-key rejection did not reach Sparkle signature validation" >&2
        exit 1
    fi
    if [[ "$(plist_value CFBundleVersion "$rejection_app")" != "$prior_build" ]]; then
        echo "rejected update changed the prior app" >&2
        exit 1
    fi
fi

generate_appcast "$private_key_file"
local_signature="$(extract_archive_signature "$feed_root/appcast.xml")"
if [[ -n "${MKV_MAGIC_EXPECTED_APPCAST_PATH:-}" ]]; then
    expected_signature="$(extract_archive_signature "$MKV_MAGIC_EXPECTED_APPCAST_PATH")"
    if [[ "$local_signature" != "$expected_signature" ]]; then
        echo "local acceptance feed does not sign the draft update archive" >&2
        exit 1
    fi
fi
curl --fail --silent --show-error "$feed_url" >/dev/null
curl --fail --silent --show-error "$download_prefix$expected_zip_name" >/dev/null

"$sparkle_cli" "$working_app" \
    --check-immediately \
    --feed-url "$feed_url" \
    --user-agent-name "MKV Magic update acceptance" \
    --verbose >"$work_root/replacement.log" 2>&1

installed_version="$(plist_value CFBundleShortVersionString "$working_app")"
installed_build="$(plist_value CFBundleVersion "$working_app")"
if [[ "$installed_version" != "$candidate_version" || \
      "$installed_build" != "$candidate_build" || \
      "$(shasum -a 256 "$working_app/Contents/MacOS/MKVMagic" | awk '{print $1}')" != \
      "$(shasum -a 256 "$candidate_app/Contents/MacOS/MKVMagic" | awk '{print $1}')" ]]; then
    echo "Sparkle did not install the exact candidate app" >&2
    exit 1
fi
codesign --verify --deep --strict --verbose=2 "$working_app"

host_architecture="$(uname -m)"
case "$host_architecture" in
    arm64|x86_64) ;;
    *) echo "unsupported updater acceptance architecture" >&2; exit 1 ;;
esac
if [[ "$require_distribution" == 1 ]]; then
    xcrun stapler validate "$working_app"
    spctl --assess --type execute --verbose=2 "$working_app"
    arch "-$host_architecture" "$working_app/Contents/MacOS/MKVMagic" \
        --run-native-release-verification >/dev/null
else
    arch "-$host_architecture" "$working_app/Contents/MacOS/MKVMagic" \
        --app-baseline-probe >/dev/null
fi

archive_digest="$(shasum -a 256 "$candidate_zip" | awk '{print $1}')"
printf 'Sparkle replaced MKV Magic %s (%s) with %s (%s) on %s; archive SHA-256 %s\n' \
    "$prior_version" "$prior_build" "$installed_version" "$installed_build" \
    "$host_architecture" "$archive_digest"
