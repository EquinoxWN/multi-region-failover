.PHONY: setup lint test check bench audit ci

# Terraform is downloaded into .tmp/bin by scripts/terraform.sh (pinned version, checksum-verified).
TF = $(CURDIR)/$(shell sh scripts/terraform.sh)
export CHECKPOINT_DISABLE = 1

setup:
	go mod download
	cd terraform && $(TF) init -input=false

# gofmt and go vet; terraform fmt and validate.
lint:
	@test -z "$$(gofmt -l cmd internal)" || (gofmt -l cmd internal; exit 1)
	go vet ./...
	$(TF) fmt -check -recursive terraform
	cd terraform && $(TF) validate

# Go tests (parity checker, cost estimate), then terraform test: 9 runs that plan and apply
# both regions against mocked AWS providers, with no AWS account.
test:
	go test -count=1 ./...
	cd terraform && $(TF) test

# Parity of the two stacks and the estimated monthly cost of each.
check:
	go run ./cmd/multi-region-failover

bench:
	@echo "M3: drill report with measured RTO and RPO, and the standby's monthly cost from the bill"

# Known vulnerabilities in the Go modules and standard library the checker calls.
audit:
	go run golang.org/x/vuln/cmd/govulncheck@v1.8.0 ./...

ci: setup lint test check
