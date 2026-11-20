# AWS Infrastructure Automation: Terraform, Jenkins, and GitHub

This project provisions an AWS network, two EC2 instances, and two private S3 buckets using reusable Terraform modules. Four independent environment roots share the modules but have separate CIDRs, sizing, tags, and remote state keys.

## Architecture and execution flow

```text
GitHub feature branch / PR
          |
          v
Jenkins multibranch pipeline
  checkout -> fmt/init/validate -> Checkov or tfsec
          -> plan + restricted plan artifacts
          -> (APPLY only) approved GitHub review
          -> authorized Jenkins approval
          -> apply the same saved plan -> AWS verification
          |
          v
AWS target role (environment-specific)
  VPC -> public subnet -> IGW -> public route table
  security group -> 2 encrypted EC2 instances
  2 versioned, encrypted, private S3 buckets
          |
          v
Versioned S3 Terraform state, one key and lock per environment
```

The bootstrap root creates the state bucket, public-access protections, encryption, versioning, and per-environment state IAM policies. The first bootstrap run uses local state only to create that bucket; the documented migration then moves bootstrap state into the same S3 bucket. Environment roots use Terraform 1.10+ native S3 lock files (`use_lockfile = true`), not DynamoDB.

`modules/platform` composes the reusable `vpc`, `security-group`, `ec2`, and `s3` modules. Environment roots set the environment name and call the platform module; resources are not duplicated between environments. With `ami_id = null`, the latest Amazon Linux 2023 x86_64 AMI is resolved from AWS Systems Manager Parameter Store. Set an explicit AMI ID in an environment's `terraform.tfvars` for a pinned, repeatable release. SSH/HTTP/HTTPS ingress defaults to no rules. Set only trusted CIDRs in the matching environment file; `key_pair_name` can be set to an existing EC2 key pair when SSH is needed.

The S3 application buckets use AWS-generated unique suffixes appended to the environment-specific prefixes, block all public access, enforce TLS, version objects, expire objects after the configured retention, and have Terraform `prevent_destroy`. This deletion protection applies in every environment, not only production.

## Project layout

```text
bootstrap-state/                  # One-time state bucket and scoped IAM policies
  backend.hcl main.tf outputs.tf provider.tf terraform.tfvars variables.tf versions.tf
modules/
  ec2/                             # Reusable EC2 instances, encrypted root volumes, IMDSv2
  platform/                        # Composition layer wiring the four resource modules
  s3/                              # Private, encrypted, versioned lifecycle-managed buckets
  security-group/                  # Configurable IPv4 ingress and outbound rules
  vpc/                             # VPC, public subnet, IGW, route table and association
environments/
  dev/                             # Independent root, tfvars, backend key and provider
  integration/
  pre/
  prod/
Jenkinsfile                        # Parameterized PR validation, plan and gated apply
.gitignore
README.md
```

Every Terraform file is included in the repository. The `terraform.tfvars` files are usable defaults for `us-east-1`; change names, CIDRs, instance sizing, ingress CIDRs, region, and tags for your account and workload.

## Prerequisites

### AWS

* An AWS account and a region that supports the selected instance types and Amazon Linux 2023.
* Terraform CLI 1.10 or later, AWS CLI v2, and credentials for the initial bootstrap. Use AWS IAM Identity Center, federation, or an assumed role rather than committing or embedding access keys.
* Bootstrap identity permissions to create/manage the state bucket and create IAM policies. Attach each generated environment state policy to only the corresponding deployment role.
* Each deployment role also needs the narrowly scoped EC2/VPC/S3/SSM read permissions to manage this stack in its environment, and a trust policy allowing the Jenkins agent's IAM role to assume it. Restrict resource creation to approved regions, tags, and account controls where supported.
* State bucket names are generated from the prefix in `bootstrap-state/terraform.tfvars`. The prefix is not an account secret and the AWS-generated suffix makes the final name unique.

### Jenkins

Use a Linux agent labeled `terraform-linux` with Terraform >=1.10, AWS CLI v2, `jq`, `gh`, and either Checkov or tfsec installed. Install Jenkins plugins for Pipeline, GitHub Branch Source (or equivalent multibranch PR discovery/status publishing), Lockable Resources, Workspace Cleanup, and AWS Steps.

Configure Jenkins global environment (non-secret values):

| Name | Value |
| --- | --- |
| `AWS_ACCOUNT_ID` | Target AWS account ID |
| `TF_ROLE_DEV` | IAM role name for dev |
| `TF_ROLE_INTEGRATION` | IAM role name for integration |
| `TF_ROLE_PRE` | IAM role name for pre |
| `TF_ROLE_PROD` | IAM role name for prod |

The Jenkins agent's instance profile/identity is used by AWS Steps (`useNode: true`) to assume only the selected environment role. Configure each target role's trust policy for that agent. Use the bootstrap output policy ARN matching each role; do not attach all four state policies to every role.

Create Jenkins Credentials Manager entries:

* `terraform-state-bucket`: Secret text containing the state bucket name output by bootstrap.
* `github-pr-read-token`: Secret text containing a GitHub token with read-only repository and pull-request access, used only to ensure a PR is open and approved before APPLY. Never use a write/merge token in this pipeline.

Restrict Jenkins job, credential, plan artifact, and approval access. Plan files and rendered plans can contain sensitive values even when Terraform marks outputs sensitive. Workspace cleanup is enabled; Jenkins build/artifact retention is limited.

## Bootstrap remote state

The backend bucket must exist before environment initialization. Bootstrap itself begins with local state because the bucket does not yet exist; migrate that state immediately after creation. Run these commands from PowerShell in the repository root:

```powershell
terraform -chdir=bootstrap-state init -backend=false
terraform -chdir=bootstrap-state apply -var-file=terraform.tfvars
$stateBucket = terraform -chdir=bootstrap-state output -raw state_bucket_name
terraform -chdir=bootstrap-state init -migrate-state `
  -backend-config=backend.hcl `
  "-backend-config=bucket=$stateBucket" `
  "-backend-config=region=us-east-1"
terraform -chdir=bootstrap-state output -json
```

Review the four `environment_state_policy_arns` outputs and attach only the matching state policy to each environment's Jenkins target role. Record the generated bucket name in Jenkins Credentials Manager. After confirming bootstrap state is in S3, remove any local `bootstrap-state/terraform.tfstate*` files from the machine using a secure, targeted cleanup; they are gitignored and must never be committed.

Each environment's `backend.hcl` fixes a distinct key, enables encryption and S3 native locking. Jenkins supplies the bucket and selected region at init time. The bootstrap bucket has versioning and public access blocking, so state history can be recovered while the backend lock file prevents simultaneous state operations.

## Local PLAN / APPLY

After bootstrap, configure AWS credentials for the matching deployment role and set the bucket name:

```powershell
$env:TF_STATE_BUCKET = $stateBucket
$env:AWS_REGION = "us-east-1"
terraform -chdir=environments/dev init `
  -backend-config=backend.hcl `
  "-backend-config=bucket=$env:TF_STATE_BUCKET" `
  "-backend-config=region=$env:AWS_REGION"
terraform -chdir=environments/dev validate
terraform -chdir=environments/dev plan `
  -var-file=terraform.tfvars `
  "-var=aws_region=$env:AWS_REGION" `
  -out=tfplan
terraform -chdir=environments/dev show -no-color tfplan
```

The command above is PLAN only; do not run `apply` unless you have reviewed the exact plan. To deploy locally after review, run `terraform -chdir=environments/dev apply tfplan`. For another environment, change the directory and assume its matching IAM role. Terraform requires explicit confirmation for an interactive apply; CI has an additional Jenkins approver gate.

## Jenkins PR and merge workflow

1. Create a feature branch and open a PR to `main`. Configure a Jenkins multibranch pipeline to discover PRs and check out the PR head; set PR trust so untrusted fork code cannot access AWS roles or GitHub credentials. Restrict who may trigger builds that receive cloud credentials.
2. `PLAN` checks out the PR, runs recursive `terraform fmt -check`, initializes and validates the selected environment, requires Checkov or tfsec, then generates and archives both the binary plan and readable `tfplan.txt`. `PLAN` has no apply stage and never invokes `terraform apply`.
3. Use `APPLY` only after a GitHub reviewer has approved the open PR. Jenkins verifies the GitHub review state, then requires a separate approval from the Jenkins `terraform-approvers` submitter group. `AUTO_APPROVE` never bypasses either gate; it is rejected for production and ignored for other environments.
4. The Terraform delivery stages acquire a shared Lockable Resources lock named for the environment. Jenkins also disables overlapping runs of the same job. Plan, approval, and apply occur under the environment lock; apply consumes the saved binary plan and fails rather than silently making a new plan if it is stale. State keys and IAM policies are environment-specific.
5. After apply, Jenkins checks the VPC, subnet, exactly two EC2 instances, and both S3 buckets, then archives Terraform outputs. No GitHub merge automation is configured.
6. Configure GitHub branch protection/rulesets for `main`: require PRs, at least one approving review, dismiss stale approvals, require the Jenkins status check for this multibranch job, require the branch to be up to date if appropriate, and prohibit force pushes and direct pushes (including administrators/bypass actors unless explicitly approved). Require Jenkins validation/security checks; when using apply-before-merge, require the APPLY job's successful status too. Do not mark the PR mergeable until deployment approval and checks have succeeded.

Applying before merge can leave live infrastructure from a PR that is later rejected or abandoned. This pipeline mitigates the risk by requiring a previously approved open PR, a distinct Jenkins approver, a serialized environment lock, environment-scoped roles/state access, and applying only the reviewed plan. It deliberately does not destroy resources automatically when a PR closes: automatic rollback could destroy shared or production data. Define an owner and expiry/reconciliation procedure for every pre-merge deployment; after PR closure, inspect state and plan an explicitly approved cleanup or keep/merge decision. Do not reuse a PR apply job for unrelated changes.

Protect the Jenkinsfile and branch source configuration as trusted code. Never expose privileged AWS or GitHub credentials to arbitrary fork PRs; restrict target-role permissions and network egress on PR agents because Terraform provider/data-source code is executed during planning. The read-only GitHub token is used only in the gated APPLY stage. Status checks and GitHub review requirements are enforced by branch protection, not by an in-repository merge script.

## Troubleshooting

* **Backend bucket not found / `terraform init` fails:** finish bootstrap first, check the `terraform-state-bucket` credential and region, and confirm the role has the matching state policy. Never switch to a different state key to work around access errors.
* **S3 lock denied or lock already held:** verify `GetObject`, `PutObject`, and `DeleteObject` access on the exact environment's `.tflock` object. Check active Jenkins builds before clearing any stale lock; force-unlock only after confirming no Terraform process is running.
* **AccessDenied during plan/apply:** confirm the selected environment role, trust relationship, deployment permissions, and state policy. Keep IAM errors visible; do not add broad administrator access as a workaround.
* **No SSH connectivity:** ingress defaults closed and no key pair is selected. Configure a real EC2 key pair and trusted `/32` or corporate CIDR in the environment tfvars, then review the plan. Instances have public IPs, but access also depends on routes, NACLs, and network policy.
* **S3 bucket name conflict:** application buckets get a generated suffix; adjust the environment prefix only if AWS rejects it. The state bucket uses an AWS-generated suffix too.
* **Plan is stale at apply:** another state update occurred after the plan. Generate and review a new plan; never apply an old binary plan or silently re-plan after approval.
* **Checkov/tfsec or validation fails:** resolve findings in code and rerun the PR checks. Install one supported scanner on the agent; the pipeline fails closed if neither exists.
* **Production approval rejected:** `AUTO_APPROVE` must remain false. Production always requires both a GitHub approval and an authorized Jenkins input approval.

## Terraform lock file and state hygiene

Each Terraform root has a committed `.terraform.lock.hcl` that pins provider versions and checksums; review updates to these files as part of dependency changes. Do not commit `.terraform/`, plans, state, local tfvars overrides, credentials, or outputs containing sensitive values.