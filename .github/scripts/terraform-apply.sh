#!/usr/bin/env bash
set -euo pipefail

required_environment=(
  STACK
  STATE_KEY
  TF_STATE_BUCKET
  TF_STATE_KMS_KEY_ID
  TF_PLAN_BUCKET
  TF_PLAN_KMS_KEY_ID
  AWS_REGION
  GITHUB_REPOSITORY
  GITHUB_REPOSITORY_ID
  GITHUB_RUN_ID
  GITHUB_RUN_ATTEMPT
  GITHUB_SHA
  GITHUB_STEP_SUMMARY
  GH_TOKEN
)

for variable_name in "${required_environment[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "Required environment variable is unset: ${variable_name}" >&2
    exit 2
  fi
done

case "${STACK}" in
  network|gateway|cluster|dns) ;;
  *)
    echo "Unsupported Terraform stack: ${STACK}" >&2
    exit 2
    ;;
esac

if [[ ! "${GITHUB_SHA}" =~ ^[0-9a-f]{40}$ ]] ||
   [[ ! "${STATE_KEY}" =~ ^[A-Za-z0-9._/-]+$ ]] ||
   [[ "${STATE_KEY}" == /* ]] ||
   [[ "${STATE_KEY}" == *".."* ]]; then
  echo "The apply context or configured state key is unsafe." >&2
  exit 2
fi

stack_directory="terraform/${STACK}"
lock_file="${stack_directory}/.terraform.lock.hcl"
if [[ ! -f "${lock_file}" ]]; then
  echo "Committed provider lock file is missing: ${lock_file}" >&2
  exit 2
fi

work_directory="$(mktemp -d)"
pointer_file="${work_directory}/pointer.json"
bundle_file="${work_directory}/reviewed-plan.tgz"
bundle_directory="${work_directory}/bundle"
apply_log="${work_directory}/apply.log"
application_file="${work_directory}/application.json"

cleanup() {
  rm -rf "${work_directory}"
}
trap cleanup EXIT HUP INT TERM
umask 077

pull_requests_json="$(gh api \
  -H "Accept: application/vnd.github+json" \
  "repos/${GITHUB_REPOSITORY}/commits/${GITHUB_SHA}/pulls")"
matching_pull_requests="$(jq \
  --arg merge_sha "${GITHUB_SHA}" \
  '[.[] | select(.merged_at != null and .merge_commit_sha == $merge_sha)]' \
  <<<"${pull_requests_json}")"

if [[ "$(jq 'length' <<<"${matching_pull_requests}")" -ne 1 ]]; then
  echo "Apply requires exactly one merged pull request associated with the main commit." >&2
  exit 1
fi

pull_request_number="$(jq -r '.[0].number' <<<"${matching_pull_requests}")"
pull_request_head_sha="$(jq -r '.[0].head.sha' <<<"${matching_pull_requests}")"
if [[ ! "${pull_request_number}" =~ ^[1-9][0-9]*$ ]] ||
   [[ ! "${pull_request_head_sha}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Merged pull-request metadata is invalid." >&2
  exit 1
fi

pointer_object_key="plans/${GITHUB_REPOSITORY_ID}/${STACK}/pull-request/${pull_request_number}/latest.json"
aws s3 cp "s3://${TF_PLAN_BUCKET}/${pointer_object_key}" "${pointer_file}" \
  --only-show-errors >/dev/null

pointer_schema="$(jq -r '.schema_version' "${pointer_file}")"
pointer_stack="$(jq -r '.stack' "${pointer_file}")"
pointer_state_key="$(jq -r '.state_key' "${pointer_file}")"
pointer_head_sha="$(jq -r '.pull_request_head_sha' "${pointer_file}")"
pointer_stack_tree_sha="$(jq -r '.stack_tree_sha' "${pointer_file}")"
pointer_terraform_version="$(jq -r '.terraform_version' "${pointer_file}")"
bundle_object_key="$(jq -r '.bundle_object_key' "${pointer_file}")"
expected_bundle_sha256="$(jq -r '.bundle_sha256' "${pointer_file}")"
pointer_run_id="$(jq -r '.run_id' "${pointer_file}")"
pointer_run_attempt="$(jq -r '.run_attempt' "${pointer_file}")"

if [[ "${pointer_schema}" != "1" ]] ||
   [[ "${pointer_stack}" != "${STACK}" ]] ||
   [[ "${pointer_state_key}" != "${STATE_KEY}" ]] ||
   [[ "${pointer_head_sha}" != "${pull_request_head_sha}" ]] ||
   [[ ! "${pointer_stack_tree_sha}" =~ ^[0-9a-f]{40}$ ]] ||
   [[ ! "${expected_bundle_sha256}" =~ ^[0-9a-f]{64}$ ]] ||
   [[ ! "${pointer_run_id}" =~ ^[1-9][0-9]*$ ]] ||
   [[ ! "${pointer_run_attempt}" =~ ^[1-9][0-9]*$ ]] ||
   [[ ! "${bundle_object_key}" =~ ^plans/[0-9]+/(network|gateway|cluster|dns)/pull-request/[0-9]+/[0-9a-f]{40}/[0-9]+-[0-9]+/reviewed-plan\.tgz$ ]]; then
  echo "The reviewed-plan pointer failed validation." >&2
  exit 1
fi

current_stack_tree_sha="$(git rev-parse "${GITHUB_SHA}:${stack_directory}")"
if [[ "${current_stack_tree_sha}" != "${pointer_stack_tree_sha}" ]]; then
  echo "The merged stack differs from the reviewed stack tree; refusing to apply." >&2
  exit 1
fi

current_terraform_version="$(terraform version -json | jq -r '.terraform_version')"
if [[ "${current_terraform_version}" != "${pointer_terraform_version}" ]]; then
  echo "Terraform version differs from the reviewed plan." >&2
  exit 1
fi

aws s3 cp "s3://${TF_PLAN_BUCKET}/${bundle_object_key}" "${bundle_file}" \
  --only-show-errors >/dev/null
actual_bundle_sha256="$(sha256sum "${bundle_file}" | awk '{print $1}')"
if [[ "${actual_bundle_sha256}" != "${expected_bundle_sha256}" ]]; then
  echo "The reviewed plan digest does not match." >&2
  exit 1
fi

mkdir -m 0700 "${bundle_directory}"
mapfile -t bundle_members < <(tar -tzf "${bundle_file}")
expected_members=("${STACK}.tfplan" "plan.txt" "metadata.json")
if [[ "${#bundle_members[@]}" -ne "${#expected_members[@]}" ]]; then
  echo "The reviewed plan bundle contains an unexpected number of entries." >&2
  exit 1
fi
for expected_member in "${expected_members[@]}"; do
  if [[ ! " ${bundle_members[*]} " =~ [[:space:]]${expected_member}[[:space:]] ]]; then
    echo "The reviewed plan bundle contains unexpected entries." >&2
    exit 1
  fi
done
tar -C "${bundle_directory}" -xzf "${bundle_file}"
for expected_file in "${STACK}.tfplan" plan.txt metadata.json; do
  if [[ ! -f "${bundle_directory}/${expected_file}" ]]; then
    echo "The reviewed plan bundle is incomplete." >&2
    exit 1
  fi
done
if [[ "$(find "${bundle_directory}" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')" != "3" ]]; then
  echo "The reviewed plan bundle contains unexpected files." >&2
  exit 1
fi

expected_workflow_ref="${GITHUB_REPOSITORY}/.github/workflows/_reusable-terraform-plan.yml@refs/pull/${pull_request_number}/merge"
if ! jq -e \
  --arg stack "${STACK}" \
  --arg state_key "${STATE_KEY}" \
  --arg pull_request_head_sha "${pull_request_head_sha}" \
  --arg stack_tree_sha "${pointer_stack_tree_sha}" \
  --arg terraform_version "${pointer_terraform_version}" \
  --arg workflow_ref "${expected_workflow_ref}" \
  --arg run_id "${pointer_run_id}" \
  --arg run_attempt "${pointer_run_attempt}" \
  '.schema_version == 1 and
   .stack == $stack and
   .state_key == $state_key and
   .pull_request_head_sha == $pull_request_head_sha and
   .stack_tree_sha == $stack_tree_sha and
   .terraform_version == $terraform_version and
   .workflow_ref == $workflow_ref and
   .run_id == ($run_id | tonumber) and
   .run_attempt == ($run_attempt | tonumber)' \
  "${bundle_directory}/metadata.json" >/dev/null; then
  echo "The reviewed plan metadata does not match its trusted pointer." >&2
  exit 1
fi

terraform -chdir="${stack_directory}" init \
  -input=false \
  -lockfile=readonly \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="key=${STATE_KEY}" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="encrypt=true" \
  -backend-config="kms_key_id=${TF_STATE_KMS_KEY_ID}" \
  -backend-config="use_lockfile=true" \
  -no-color >/dev/null

set +e
terraform -chdir="${stack_directory}" apply \
  -input=false \
  -lock-timeout=5m \
  -no-color \
  "${bundle_directory}/${STACK}.tfplan" >"${apply_log}" 2>&1
apply_exit_code=$?
set -e

application_object_key="applications/${GITHUB_REPOSITORY_ID}/${STACK}/${GITHUB_SHA}/${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
aws s3 cp "${apply_log}" "s3://${TF_PLAN_BUCKET}/${application_object_key}/apply.log" \
  --only-show-errors \
  --sse aws:kms \
  --sse-kms-key-id "${TF_PLAN_KMS_KEY_ID}" >/dev/null

if [[ "${apply_exit_code}" -ne 0 ]]; then
  echo "Terraform apply failed. The potentially sensitive log is retained in the private plan bucket." >&2
  exit "${apply_exit_code}"
fi

jq -n \
  --arg stack "${STACK}" \
  --arg applied_commit_sha "${GITHUB_SHA}" \
  --arg pull_request_number "${pull_request_number}" \
  --arg pull_request_head_sha "${pull_request_head_sha}" \
  --arg bundle_sha256 "${actual_bundle_sha256}" \
  --arg run_id "${GITHUB_RUN_ID}" \
  --arg run_attempt "${GITHUB_RUN_ATTEMPT}" \
  '{
    schema_version: 1,
    stack: $stack,
    applied_commit_sha: $applied_commit_sha,
    pull_request_number: ($pull_request_number | tonumber),
    pull_request_head_sha: $pull_request_head_sha,
    bundle_sha256: $bundle_sha256,
    run_id: ($run_id | tonumber),
    run_attempt: ($run_attempt | tonumber)
  }' >"${application_file}"
aws s3 cp "${application_file}" "s3://${TF_PLAN_BUCKET}/${application_object_key}/application.json" \
  --only-show-errors \
  --sse aws:kms \
  --sse-kms-key-id "${TF_PLAN_KMS_KEY_ID}" >/dev/null

{
  echo "### Terraform ${STACK} apply"
  echo
  echo "- Applied commit: \`${GITHUB_SHA}\`"
  echo "- Reviewed PR: #${pull_request_number}"
  echo "- Reviewed head: \`${pull_request_head_sha}\`"
  echo "- Plan digest: \`${actual_bundle_sha256}\`"
  echo
  echo "The exact encrypted plan produced for the merged PR was applied."
} >>"${GITHUB_STEP_SUMMARY}"
