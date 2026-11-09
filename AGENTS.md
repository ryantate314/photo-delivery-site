# AGENTS.md

Instructions for AI coding agents working in this repo. This is the photo delivery site monorepo: Angular `frontend/`, Lambda `api/`, and Terraform `infra/`. The shared account baseline (state bucket, boundary policy, VPCs, Route 53 zone ownership decisions) lives in the separate `aws-infrastructure` repo; read its `AGENTS.md` and `docs/` when in doubt.

## Layout
- `frontend/` Angular 20 app (npm). Built output is synced to `s3://<bucket>/site/`.
- `api/` Lambda code (Node 22, TypeScript, esbuild).
- `infra/` Terraform root for the `photos` workload. S3 backend, state key `workloads/photos/prod/terraform.tfstate` in the shared state bucket. Terraform >= 1.10, AWS provider `~> 6.0`.
- `Makefile` is the only deploy path (no CI deploys, no OIDC).

## Hard rules (do not violate without the owner's explicit approval)
1. **Cost.** No NAT Gateway, ALB/NLB, WAF, interface VPC endpoints, OpenSearch, RDS/Aurora, ElastiCache or any fixed-monthly-cost resource. Prefer Lambda outside a VPC, S3, CloudFront, DynamoDB on-demand, API Gateway HTTP API. Optional paid things default to off. Quote the monthly cost of any new resource in the summary.
2. **Secrets.** No secrets, tokens, keys, passwords, emails or other PII in committed files (`.tf`, `.tfvars`, code, docs, git config files). No IAM users or access keys: use SSO for humans. Reference SSM/Secrets Manager by name only. Do not put customer, shoot or album names in committed files or tests (use synthetic names).
3. **State.** Never commit Terraform state. Never run `terraform state rm`, `force-unlock` or `import` against live state without approval.
4. **Live resources.** The site is live. Never apply a plan that destroys or replaces an existing resource without the owner reading it.
5. **Never apply without being asked.** `terraform plan`, tests and builds are fine. `terraform apply`/`destroy`, `aws s3 sync`, CloudFront invalidations and any other AWS write need explicit instruction. Inventory work uses the read-only `inventory` SSO profile only.
6. **Buckets stay private.** Account-wide S3 Block Public Access is on. Serve content through CloudFront + OAC only.
7. **Git.** Commit as `Ryan Tate` with the personal identity (set repo-local `user.name`/`user.email`). Never force-push or rewrite pushed history without explicit approval.

## Conventions
- Names for new resources: `${env}-photodeliverysite-${purpose}` (e.g. `prod-photodeliverysite-api`), lowercase, hyphens, via `local.name`. Existing adopted resources keep their console-era names until they are replaced (e.g. by the DynamoDB API rewrite). The Terraform `workload` (`photos`), state key and `Workload` tag stay as they are. Tags come from provider `default_tags`.
- Every S3 bucket: public access block, `BucketOwnerEnforced`, SSE, TLS-only policy, lifecycle rule.
- Workload IAM roles attach the `workload-permissions-boundary` policy.
- Pin provider versions; commit `.terraform.lock.hcl`.
- If AWS CLI/Terraform fails with TLS errors behind the corporate proxy, set `AWS_CA_BUNDLE`/`SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt`. Never disable TLS verification.

## Verify before finishing a change
Use `make check` once the Makefile exists. Until then: `npm ci && npm run build && npm test -- --watch=false --browsers=ChromeHeadless` in `frontend/`, and `terraform fmt -recursive && terraform init -backend=false && terraform validate` in `infra/`.
