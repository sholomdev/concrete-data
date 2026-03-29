# concrete-data — developer shortcuts
# Usage: make <target>

.PHONY: help install pipeline-dev dbt-dev dashboard-dev test-pipeline test-dbt \
        pipeline-prod dbt-prod full-refresh fmt lint clean

DUCKDB_PATH ?= $(shell pwd)/concrete_data_dev.duckdb

help:
	@echo ""
	@echo "  Development"
	@echo "  -----------"
	@echo "  make install         Install all Python + Node deps"
	@echo "  make pipeline-dev    Run dlt pipeline → DuckDB"
	@echo "  make dbt-dev         Run dbt models + tests → DuckDB"
	@echo "  make dashboard-dev   Start Evidence dev server (DuckDB)"
	@echo "  make dev             Run all three in sequence"
	@echo ""
	@echo "  Testing"
	@echo "  -------"
	@echo "  make test-pipeline   Smoke-test the dlt source"
	@echo "  make test-dbt        dbt compile + test (DuckDB)"
	@echo "  make lint            Ruff lint on pipeline/"
	@echo ""
	@echo "  Production (requires GCP auth)"
	@echo "  -------"
	@echo "  make pipeline-prod   Run dlt → BigQuery"
	@echo "  make dbt-prod        Run dbt → BigQuery"
	@echo "  make full-refresh    Drop + reload all data (prod)"
	@echo ""
	@echo "  Infra"
	@echo "  -----"
	@echo "  make tf-plan         terraform plan"
	@echo "  make tf-apply        terraform apply"
	@echo ""

install:
	pip install -r pipeline/requirements.txt
	pip install -r transform/requirements.txt
	cd dashboard && npm install
	cd transform && dbt deps

# ── Dev pipeline ─────────────────────────────────────────────────────────────

pipeline-dev:
	cd pipeline && ENV=dev DUCKDB_PATH=$(DUCKDB_PATH) python pipeline.py

dbt-dev:
	cd transform && \
	  ENV=dev DUCKDB_PATH=$(DUCKDB_PATH) DBT_PROFILES_DIR=. \
	  dbt run --target dev --profiles-dir . && \
	  ENV=dev DUCKDB_PATH=$(DUCKDB_PATH) DBT_PROFILES_DIR=. \
	  dbt test --target dev --profiles-dir .

dashboard-dev:
	cd dashboard && \
	  EVIDENCE_SOURCE__DEFAULT__CONNECTOR=duckdb \
	  EVIDENCE_SOURCE__DEFAULT__FILENAME=$(DUCKDB_PATH) \
	  npm run dev

dev: pipeline-dev dbt-dev
	@echo "Run 'make dashboard-dev' to start the Evidence server."

# ── Prod pipeline ─────────────────────────────────────────────────────────────

pipeline-prod:
	cd pipeline && ENV=prod python pipeline.py

dbt-prod:
	cd transform && \
	  ENV=prod DBT_PROFILES_DIR=. \
	  dbt source freshness --target prod --profiles-dir . && \
	  dbt run --target prod --profiles-dir . && \
	  dbt test --target prod --profiles-dir . --store-failures

full-refresh:
	cd pipeline && ENV=prod python pipeline.py --full
	$(MAKE) dbt-prod

# ── Testing / lint ─────────────────────────────────────────────────────────

test-pipeline:
	ENV=dev DUCKDB_PATH=$(DUCKDB_PATH) pytest pipeline/tests/ -v

test-dbt:
	cd transform && \
	  ENV=dev DUCKDB_PATH=$(DUCKDB_PATH) DBT_PROFILES_DIR=. \
	  dbt compile --target dev --profiles-dir . && \
	  dbt test --target dev --profiles-dir .

lint:
	ruff check pipeline/ --config pyproject.toml
	ruff format --check pipeline/ --config pyproject.toml

fmt:
	ruff format pipeline/ --config pyproject.toml

# ── Terraform ─────────────────────────────────────────────────────────────

tf-plan:
	cd infra && terraform plan \
	  -var="project_id=$(GCP_PROJECT_ID)" \
	  -var="github_repo=sholomdev/concrete-data"

tf-apply:
	cd infra && terraform apply \
	  -var="project_id=$(GCP_PROJECT_ID)" \
	  -var="github_repo=sholomdev/concrete-data"

# ── Cleanup ───────────────────────────────────────────────────────────────

clean:
	rm -f concrete_data_dev.duckdb concrete_data_dev.duckdb.wal
	rm -rf transform/target transform/dbt_packages transform/logs
	rm -rf dashboard/.evidence dashboard/build dashboard/node_modules
	rm -rf pipeline/__pycache__ pipeline/sources/__pycache__
