# Makefile for Ethereum Balance API (FastAPI + uv)

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Configurable variables
AWS_REGION := us-west-2
# Hard-coded ECR settings
ECR_REGISTRY := 703110344528.dkr.ecr.us-west-2.amazonaws.com
ECR_REGION := us-west-2
ECR_REPOSITORY := int/balance-api
ECR_IMAGE := $(ECR_REGISTRY)/$(ECR_REPOSITORY)
IMAGE := $(ECR_IMAGE)
TAG := latest
IMAGEDIGEST_SSM ?= /int/balance-api/image_digest
INFURA_PROJECT_ID ?= f3c095656381439aa1acb1722d9c62f2

# Terraform variables
TF_DIR := terraform
TF_VARS := -var="aws_region=$(AWS_REGION)" -var="container_image=$(IMAGE):$(TAG)" -var="infura_project_id=$(INFURA_PROJECT_ID)"
BOOTSTRAP_DIR := bootstrap

## help: Show this help message
help:
	@grep -E '^##' $(MAKEFILE_LIST) | sed -e 's/^## \(.*\)/\1/'

## uv-check: Verify uv is installed
uv-check:
	@command -v uv >/dev/null 2>&1 || { echo "uv not found. Install with: pip install uv (or brew install uv)"; exit 1; }

## venv: Create a local virtual environment via uv
venv: uv-check
	uv venv

## install: Install project dependencies into the venv
install: uv-check
	uv pip install -e .

## run: Start the FastAPI server locally
run: uv-check
	@if [ -z "$(INFURA_PROJECT_ID)" ]; then echo "Set INFURA_PROJECT_ID first"; exit 1; fi
	uv run uvicorn src.app:app --host 0.0.0.0 --port 3000

## docker-build: Build the Docker image (ECR latest)
docker-build:
	docker build -t $(IMAGE):$(TAG) .

## docker-run: Run the Docker image locally (requires INFURA_PROJECT_ID)
docker-run: docker-build
	@if [ -z "$(INFURA_PROJECT_ID)" ]; then echo "Set INFURA_PROJECT_ID first"; exit 1; fi
	docker run --rm -e INFURA_PROJECT_ID=$(INFURA_PROJECT_ID) -p 3000:3000 $(IMAGE):$(TAG)

## docker-push: Push the image to ECR latest (ensure ecr-login)
docker-push:
	docker push $(IMAGE):$(TAG)

## ecr-login: Authenticate Docker to Amazon ECR
ecr-login:
	aws ecr get-login-password --region $(ECR_REGION) | docker login --username AWS --password-stdin $(ECR_REGISTRY)

## ecr-build: Build and push multi-arch (amd64, arm64) image to ECR latest, then publish digest to SSM
ecr-build: ecr-login
	# Ensure a reusable buildx builder exists
	@docker buildx inspect multiarch-builder >/dev/null 2>&1 || docker buildx create --name multiarch-builder --use
	docker buildx build \
	  --platform linux/amd64,linux/arm64 \
	  -t $(ECR_IMAGE):$(TAG) \
	  --push .
	$(MAKE) ssm-publish

## ssm-publish: Publish the latest image digest to SSM for Terraform to consume
ssm-publish:
	@echo "Fetching digest for $(ECR_IMAGE):$(TAG) and publishing to $(IMAGEDIGEST_SSM)"
	@DIGEST=$$(aws ecr describe-images --region $(ECR_REGION) --repository-name $(ECR_REPOSITORY) --image-ids imageTag=$(TAG) --query 'imageDetails[0].imageDigest' --output text); \
	FULL_REF="$(ECR_IMAGE)@$$DIGEST"; \
	aws ssm put-parameter --region $(ECR_REGION) --name $(IMAGEDIGEST_SSM) --type String --overwrite --value "$$FULL_REF"

## ecr-push: Push image to ECR latest (requires ecr-login)
ecr-push:
	docker push $(ECR_IMAGE):$(TAG)

## ecr-build-push: Alias for ecr-build (multi-arch build and push)
ecr-build-push: ecr-build

## tf-init: Initialize Terraform in $(TF_DIR)
tf-init:
	cd $(TF_DIR) && terraform init -backend-config=backend.hcl

## tf-plan: Terraform plan with current settings
tf-plan:
	@if [ -z "$(INFURA_PROJECT_ID)" ]; then echo "Set INFURA_PROJECT_ID for Terraform"; exit 1; fi
	cd $(TF_DIR) && terraform plan $(TF_VARS)

## tf-apply: Terraform apply (creates/updates infrastructure)
tf-apply:
	@if [ -z "$(INFURA_PROJECT_ID)" ]; then echo "Set INFURA_PROJECT_ID for Terraform"; exit 1; fi
	cd $(TF_DIR) && terraform apply $(TF_VARS)

## tf-destroy: Terraform destroy (tears down infrastructure)
tf-destroy:
	cd $(TF_DIR) && terraform destroy $(TF_VARS)

## tf-bootstrap: Create S3 backend bucket (local state)
tf-bootstrap:
	cd $(BOOTSTRAP_DIR) && terraform init && terraform apply -auto-approve -var="aws_region=$(AWS_REGION)"
	@echo "Copy terraform/backend.hcl.example to terraform/backend.hcl and fill the bucket name with the bootstrap output."

## clean: Remove local build artifacts and caches
clean:
	rm -rf .venv __pycache__ **/__pycache__ .pytest_cache .mypy_cache

.PHONY: help uv-check venv install run docker-build docker-run docker-push tf-init tf-plan tf-apply tf-destroy clean


