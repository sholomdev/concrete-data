# concrete-data — developer shortcuts
.PHONY: help install pipeline-dev dbt-dev dashboard-dev dev \
        test-pipeline test-dbt lint fmt \
        build-image push-image run-job \
        tf-plan tf-apply clean

DUCKDB_PATH    ?= $(shell pwd)/concrete_data_dev.duckdb
GCP_PROJECT_ID ?= $(shell gcloud config get-value project 2>/dev/null)
GCP_REGION     ?= us-central1
IMAGE_URL      ?= $(GCP_REGION)-docker.pkg.dev/$(GCP_PROJECT_ID)/concrete-data/pipeline

help:
	@echo ""
	@echo "  Local development"
	@echo "  make install         Install all Python + Node deps"
	@echo "  make pipeline-dev    dlt → DuckDB"
	@echo "  make dbt-dev         dbt run + test → DuckDB"
	@echo "  make dashboard-dev   Evidence dev server (DuckDB, localhost:3000)"
	@echo "  make dev             pipeline-dev + dbt-dev"
	@echo ""
	@echo "  Testing / lint"
	@echo "  make test-pipeline   pytest smoke tests (DuckDB)"
	@echo "  make test-dbt        dbt compile + test (DuckDB)"
	@echo "  make lint            ruff check"
	@echo "  make fmt             ruff format"
	@echo ""
	@echo "  Docker / Cloud Run"
	@echo "  make build-image     Build Docker image locally"
	@echo "  make push-image      Build + push to Artifact Registry"
	@echo "  make run-job         Trigger Cloud Run Job and stream logs"
	@echo ""
	@echo "  Terraform"
	@echo "  make tf-plan         terraform plan"
	@echo "  make tf-apply        terraform apply"
	@echo ""

install:
	pip install -r pipeline/requirements.txt
	pip install -r transform/requirements.txt
	cd dashboard && npm install
	cd transform && dbt deps

# ── Dev ───────────────────────────────────────────────────────────────────────

pipeline-dev:
	cd pipeline && ENV=dev DUCKDB_PATH=$(DUCKDB_PATH) python pipeline.py

dbt-dev:
	cd transform && \
	  ENV=dev DUCKDB_PATH=$(DUCKDB_PATH) \
	  dbt run  --target dev --profiles-dir . && \
	  ENV=dev DUCKDB_PATH=$(DUCKDB_PATH) \
	  dbt test --target dev --profiles-dir .

dashboard-dev:
	cd dashboard && \
	  EVIDENCE_SOURCE__DEFAULT__CONNECTOR=duckdb \
	  EVIDENCE_SOURCE__DEFAULT__FILENAME=$(DUCKDB_PATH) \
	  npm run dev

dev: pipeline-dev dbt-dev
	@echo "Run 'make dashboard-dev' to start the Evidence server."

# ── Testing / lint ────────────────────────────────────────────────────────────

test-pipeline:
	ENV=dev DUCKDB_PATH=$(DUCKDB_PATH) pytest pipeline/tests/ -v

test-dbt:
	cd transform && \
	  ENV=dev DUCKDB_PATH=$(DUCKDB_PATH) \
	  dbt compile --target dev --profiles-dir . && \
	  dbt test   --target dev --profiles-dir .

lint:
	ruff check pipeline/ --config pyproject.toml
	ruff format --check pipeline/ --config pyproject.toml

fmt:
	ruff format pipeline/ --config pyproject.toml

# ── Docker / Cloud Run ────────────────────────────────────────────────────────

build-image:
	docker build -t $(IMAGE_URL):local .

push-image:
	gcloud auth configure-docker $(GCP_REGION)-docker.pkg.dev --quiet
	docker build \
	  --tag $(IMAGE_URL):local \
	  --tag $(IMAGE_URL):latest \
	  .
	docker push $(IMAGE_URL):local
	docker push $(IMAGE_URL):latest

run-job:
	gcloud run jobs execute nyc-311-pipeline \
	  --region $(GCP_REGION) \
	  --wait

# ── Terraform ─────────────────────────────────────────────────────────────────

tf-plan:
	cd infra && terraform plan \
	  -var="project_id=$(GCP_PROJECT_ID)" \
	  -var="github_repo=sholomdev/concrete-data" \
	  -var="region=$(GCP_REGION)"

tf-apply:
	cd infra && terraform apply \
	  -var="project_id=$(GCP_PROJECT_ID)" \
	  -var="github_repo=sholomdev/concrete-data" \
	  -var="region=$(GCP_REGION)"

# ── Cleanup ───────────────────────────────────────────────────────────────────

clean:
	rm -f concrete_data_dev.duckdb concrete_data_dev.duckdb.wal
	rm -rf transform/target transform/dbt_packages transform/logs
	rm -rf dashboard/.evidence dashboard/build dashboard/node_modules
	rm -rf pipeline/__pycache__ pipeline/sources/__pycache__
