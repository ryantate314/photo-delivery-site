# Deploy workflow: everything runs from a laptop via SSO. No CI deploys.
#   make check        format/validate/build/test everything (no AWS access needed)
#   make plan         terraform plan, saved to infra/.tfplan (read-only)
#   make apply        apply the SAVED plan after a confirmation prompt (AWS write)
#   make deploy-web   build Angular and sync it to s3://<bucket>/site, then invalidate CloudFront
# Set AWS_PROFILE to the SSO profile with Terraform rights, e.g.  AWS_PROFILE=terraform make plan
# Behind a TLS-inspecting proxy: export AWS_CA_BUNDLE=SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

INFRA := infra
WEB   := frontend
WEB_DIST := $(WEB)/dist/photos/browser
PLAN_MAX_AGE_MIN := 30

export AWS_PAGER :=

.PHONY: help install check fmt validate test-web build-web plan apply deploy-web require-profile

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

require-profile:
	@[ -n "$${AWS_PROFILE:-}" ] || { echo "Set AWS_PROFILE (SSO profile), e.g. AWS_PROFILE=terraform make $(MAKECMDGOALS)" >&2; exit 1; }

install: ## npm ci for the frontend, terraform init for infra (needs AWS_PROFILE for the S3 backend)
	cd $(WEB) && npm ci
	cd $(INFRA) && terraform init -input=false

fmt: ## Format Terraform
	cd $(INFRA) && terraform fmt -recursive

validate: ## terraform fmt -check and validate (no backend, no AWS)
	cd $(INFRA) && terraform fmt -recursive -check
	cd $(INFRA) && export TF_DATA_DIR=.terraform-validate && terraform init -backend=false -input=false >/dev/null && terraform validate
	@if grep -rnE 'aws_nat_gateway|aws_networkfirewall|aws_lb\b|aws_wafv2' --include=*.tf . ; then echo "forbidden fixed-cost resource found" >&2; exit 1; fi

test-web: ## Frontend unit tests (headless)
	cd $(WEB) && npm test -- --watch=false --browsers=ChromeHeadless

build-web: ## Production build of the Angular app
	cd $(WEB) && npm run build

check: validate build-web test-web ## Everything that doesn't touch AWS

plan: require-profile ## terraform plan -> infra/.tfplan (read-only)
	cd $(INFRA) && terraform init -input=false >/dev/null && terraform plan -input=false -out=.tfplan
	@echo; echo "Review the plan above. Anything marked 'replaced' or 'destroyed' on a live resource needs the owner's sign-off."

apply: require-profile ## Apply the saved plan (prompts; refuses stale or missing plans)
	@test -f $(INFRA)/.tfplan || { echo "No saved plan. Run 'make plan' first." >&2; exit 1; }
	@if [ -n "$$(find $(INFRA)/.tfplan -mmin +$(PLAN_MAX_AGE_MIN))" ]; then echo "Saved plan is older than $(PLAN_MAX_AGE_MIN) min. Re-run 'make plan'." >&2; exit 1; fi
	@echo "Account: $$(aws sts get-caller-identity --query Account --output text)  Profile: $$AWS_PROFILE"
	@read -r -p "Apply infra/.tfplan to this account? Type 'apply' to continue: " a; [ "$$a" = apply ] || { echo aborted; exit 1; }
	cd $(INFRA) && terraform apply -input=false .tfplan
	@rm -f $(INFRA)/.tfplan

# Content only. The API ships through plan/apply (Terraform packages api/ into the Lambdas).
# --delete is limited to the site/ prefix; images/ is never touched.
deploy-web: require-profile build-web ## Sync the Angular build to s3://<bucket>/site and invalidate CloudFront
	@bucket=$$(cd $(INFRA) && terraform output -raw site_bucket); dist=$$(cd $(INFRA) && terraform output -raw cloudfront_distribution_id); \
	test -n "$$bucket" -a -n "$$dist" || { echo "Terraform outputs missing; apply the infra first." >&2; exit 1; }; \
	echo "Deploying $(WEB_DIST) -> s3://$$bucket/site (distribution $$dist)"; \
	read -r -p "Type 'deploy' to continue: " a; [ "$$a" = deploy ] || { echo aborted; exit 1; }; \
	aws s3 sync $(WEB_DIST) s3://$$bucket/site --delete --exclude index.html --cache-control "public,max-age=31536000,immutable"; \
	aws s3 cp $(WEB_DIST)/index.html s3://$$bucket/site/index.html --cache-control "no-cache" --content-type "text/html"; \
	aws cloudfront create-invalidation --distribution-id $$dist --paths "/index.html" "/" >/dev/null; \
	echo "Done."
