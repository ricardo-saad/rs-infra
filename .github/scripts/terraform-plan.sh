#!/usr/bin/env bash
set -euo pipefail

required_environment=(
  STACK
  STATE_KEY
  TFVARS_CONTENT
  TF_STATE_BUCKET
  TF_STATE_KMS_KEY_ID
  TF_PLAN_BUCKET
  TF_PLAN_KMS_KEY_ID
  AWS_REGION
  GITHUB_EVENT_PULL_REQUEST_NUMBER
  GITHUB_EVENT_PULL_REQUEST_HEAD_SHA
  GITHUB_REPOSITORY_ID
  GITHUB_RUN_ID
  GITHUB_RUN_ATTEMPT
  GITHUB_SHA
  GITHUB_WORKFLOW_REF
  GITHUB_OUTPUT
  GITHUB_STEP_SUMMARY
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

if [[ ! "${STATE_KEY}" =~ ^[A-Za-z0-9._/-]+$ ]] ||
   [[ "${STATE_KEY}" == /* ]] ||
   [[ "${STATE_KEY}" == *".."* ]]; then
  echo "The configured state key is unsafe." >&2
  exit 2
fi

stack_directory="terraform/${STACK}"
lock_file="${stack_directory}/.terraform.lock.hcl"
if [[ ! -f "${lock_file}" ]]; then
  echo "Commit ${lock_file} before producing a deployable plan." >&2
  exit 2
fi

pull_request_number="${GITHUB_EVENT_PULL_REQUEST_NUMBER:-}"
pull_request_head_sha="${GITHUB_EVENT_PULL_REQUEST_HEAD_SHA:-}"
if [[ ! "${pull_request_number}" =~ ^[1-9][0-9]*$ ]] ||
   [[ ! "${pull_request_head_sha}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "A trusted pull-request number and head SHA are required." >&2
  exit 2
fi

work_directory="$(mktemp -d)"
tfvars_file="${work_directory}/${STACK}.auto.tfvars"
plan_file="${work_directory}/${STACK}.tfplan"
plan_log="${work_directory}/plan.log"
plan_text="${work_directory}/plan.txt"
plan_json="${work_directory}/plan.json"
metadata_file="${work_directory}/metadata.json"
pointer_file="${work_directory}/pointer.json"
bundle_file="${work_directory}/reviewed-plan.tgz"

cleanup() {
  rm -rf "${work_directory}"
}
trap cleanup EXIT HUP INT TERM

umask 077
printf '%s' "${TFVARS_CONTENT}" >"${tfvars_file}"

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
terraform -chdir="${stack_directory}" plan \
  -input=false \
  -lock-timeout=5m \
  -detailed-exitcode \
  -out="${plan_file}" \
  -var-file="${tfvars_file}" \
  -no-color >"${plan_log}" 2>&1
plan_exit_code=$?
set -e

if [[ "${plan_exit_code}" -ne 0 && "${plan_exit_code}" -ne 2 ]]; then
  echo "Terraform plan failed. The output is intentionally not printed because plans may contain private topology." >&2
  exit "${plan_exit_code}"
fi

terraform -chdir="${stack_directory}" show \
  -no-color \
  "${plan_file}" >"${plan_text}"
terraform -chdir="${stack_directory}" show \
  -json \
  "${plan_file}" >"${plan_json}"

create_count="$(jq '[.resource_changes[]? | select(.change.actions | index("create"))] | length' "${plan_json}")"
update_count="$(jq '[.resource_changes[]? | select(.change.actions | index("update"))] | length' "${plan_json}")"
delete_count="$(jq '[.resource_changes[]? | select(.change.actions | index("delete"))] | length' "${plan_json}")"
replace_count="$(jq '[.resource_changes[]? | select((.change.actions | index("create")) and (.change.actions | index("delete")))] | length' "${plan_json}")"
stack_tree_sha="$(git rev-parse "HEAD:${stack_directory}")"
terraform_version="$(terraform version -json | jq -r '.terraform_version')"

object_prefix="plans/${GITHUB_REPOSITORY_ID}/${STACK}/pull-request/${pull_request_number}/${pull_request_head_sha}/${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
bundle_object_key="${object_prefix}/reviewed-plan.tgz"
pointer_object_key="plans/${GITHUB_REPOSITORY_ID}/${STACK}/pull-request/${pull_request_number}/latest.json"

jq -n \
  --arg stack "${STACK}" \
  --arg state_key "${STATE_KEY}" \
  --arg pull_request_number "${pull_request_number}" \
  --arg pull_request_head_sha "${pull_request_head_sha}" \
  --arg planned_commit_sha "${GITHUB_SHA}" \
  --arg stack_tree_sha "${stack_tree_sha}" \
  --arg terraform_version "${terraform_version}" \
  --arg workflow_ref "${GITHUB_WORKFLOW_REF}" \
  --arg run_id "${GITHUB_RUN_ID}" \
  --arg run_attempt "${GITHUB_RUN_ATTEMPT}" \
  '{
    schema_version: 1,
    stack: $stack,
    state_key: $state_key,
    pull_request_number: ($pull_request_number | tonumber),
    pull_request_head_sha: $pull_request_head_sha,
    planned_commit_sha: $planned_commit_sha,
    stack_tree_sha: $stack_tree_sha,
    terraform_version: $terraform_version,
    workflow_ref: $workflow_ref,
    run_id: ($run_id | tonumber),
    run_attempt: ($run_attempt | tonumber)
  }' >"${metadata_file}"

tar -C "${work_directory}" -czf "${bundle_file}" \
  "$(basename "${plan_file}")" \
  "$(basename "${plan_text}")" \
  "$(basename "${metadata_file}")"
bundle_sha256="$(sha256sum "${bundle_file}" | awk '{print $1}')"

jq -n \
  --arg stack "${STACK}" \
  --arg state_key "${STATE_KEY}" \
  --arg pull_request_head_sha "${pull_request_head_sha}" \
  --arg stack_tree_sha "${stack_tree_sha}" \
  --arg terraform_version "${terraform_version}" \
  --arg bundle_object_key "${bundle_object_key}" \
  --arg bundle_sha256 "${bundle_sha256}" \
  --arg run_id "${GITHUB_RUN_ID}" \
  --arg run_attempt "${GITHUB_RUN_ATTEMPT}" \
  '{
    schema_version: 1,
    stack: $stack,
    state_key: $state_key,
    pull_request_head_sha: $pull_request_head_sha,
    stack_tree_sha: $stack_tree_sha,
    terraform_version: $terraform_version,
    bundle_object_key: $bundle_object_key,
    bundle_sha256: $bundle_sha256,
    run_id: ($run_id | tonumber),
    run_attempt: ($run_attempt | tonumber)
  }' >"${pointer_file}"

# The bucket policy denies this exact PutObject unless If-None-Match is
# present, so a bug or retry can never silently replace a bundle a reviewer
# already approved; aws s3 cp does not support conditional headers.
aws s3api put-object \
  --bucket "${TF_PLAN_BUCKET}" \
  --key "${bundle_object_key}" \
  --body "${bundle_file}" \
  --if-none-match '*' \
  --server-side-encryption aws:kms \
  --ssekms-key-id "${TF_PLAN_KMS_KEY_ID}" >/dev/null
aws s3 cp "${pointer_file}" "s3://${TF_PLAN_BUCKET}/${pointer_object_key}" \
  --only-show-errors \
  --sse aws:kms \
  --sse-kms-key-id "${TF_PLAN_KMS_KEY_ID}" >/dev/null

{
  echo "status=$([[ "${plan_exit_code}" -eq 2 ]] && echo changes || echo no-changes)"
  echo "creates=${create_count}"
  echo "updates=${update_count}"
  echo "deletes=${delete_count}"
  echo "replacements=${replace_count}"
  echo "bundle_sha256=${bundle_sha256}"
} >>"${GITHUB_OUTPUT}"

{
  echo "### Terraform ${STACK} plan"
  echo
  echo "- Status: $([[ "${plan_exit_code}" -eq 2 ]] && echo changes || echo no-changes)"
  echo "- Creates: ${create_count}"
  echo "- Updates: ${update_count}"
  echo "- Deletes: ${delete_count}"
  echo "- Replacements: ${replace_count}"
  echo "- Reviewed head: \`${pull_request_head_sha}\`"
  echo "- Private plan digest: \`${bundle_sha256}\`"
  echo
  echo "The complete plan is encrypted in the private plan bucket and is not printed to public logs."
} >>"${GITHUB_STEP_SUMMARY}"
