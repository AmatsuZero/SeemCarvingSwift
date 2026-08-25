#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
demo_dir="${script_dir:h}"
swift_dir="${demo_dir}/swift"
web_dir="${demo_dir}/web"
sdk_id="swift-6.3.3-RELEASE_wasm"
artifact_dir="${swift_dir}/.build/plugins/PackageToJS/outputs/Package"
generated_dir="${web_dir}/src/generated"
entry_loader="${artifact_dir}/index.js"

if ! swift sdk list | grep -Fqx "${sdk_id}"; then
  print -u2 "Missing required Swift SDK: ${sdk_id}"
  exit 1
fi

rm -rf "${generated_dir}"
mkdir -p "${generated_dir}"
(
  cd "${swift_dir}"
  swift package --disable-sandbox --swift-sdk "${sdk_id}" js --product WasmBridgeWorker
)

if [[ ! -d "${artifact_dir}" ]]; then
  print -u2 "PackageToJS artifact directory is missing: ${artifact_dir}"
  exit 1
fi
if [[ ! -f "${entry_loader}" ]]; then
  print -u2 "PackageToJS entry loader is missing: ${entry_loader}"
  exit 1
fi
if ! find "${artifact_dir}" -type f -name '*.wasm' -print -quit | grep -q .; then
  print -u2 "PackageToJS artifact does not contain a WASM module"
  exit 1
fi

cp -R "${artifact_dir}/." "${generated_dir}/"
[[ -f "${generated_dir}/index.js" ]]
find "${generated_dir}" -type f -name '*.wasm' -print -quit | grep -q .
