## Ethereum Balance API - Design and Deployment

### Overview
This service exposes a simple HTTP endpoint implemented in Python with FastAPI. It retrieves an Ethereum address balance via Infura API. It is containerized, deployable to AWS ECS Fargate via Terraform, and ships with a CI workflow to build and push the image.

## Basic Usage for Presentation

## Health Endpoint

`curl balance-api-1857254788.us-west-2.elb.amazonaws.com/healthz`

## Non-checksum address
`curl balance-api-1857254788.us-west-2.elb.amazonaws.com/address/balance/0xc94770007dDa54cF92009BFF0dE90c06F603a09f`

## Checksum address
`curl balance-api-1857254788.us-west-2.elb.amazonaws.com/address/balance/0xc94770007dda54cF92009BFF0dE90c06F603a09f`

### API Contract
- Route: `GET /address/balance/:address`
- Params:
  - `address` (path): Ethereum address; MUST be 0x-prefixed and EIP-55 checksummed
- Behavior:
  - Network: mainnet only
  - Block tag: `latest` only
  - Caching: in-memory TTL (default 5s), configurable via `CACHE_TTL_SECONDS`
- Response (200):
```json
{
  "address": "0xC94770007dDa54cF92009BFF0dE90c06F603a09f",
  "network": "mainnet",
  "blockTag": "latest",
  "balance": "0.0001365",
  "balanceWei": "136500000000000",
  "rpcLatencyMs": 45,
  "headBlockNumber": "0x1234abcd"
}
```
- Errors: `400` for invalid address; `502` for upstream provider errors; `500` otherwise.

### Why wei vs ether matters (practical)
- On-chain JSON-RPC uses wei (hex). UI uses ether. Mixing units causes 1e18 mistakes. We return both: `balance` (ether, string) and `balanceWei` (string) to avoid precision loss.

### Which block tag to query
- For this PoC: `latest` only (tiny reorg risk acceptable). Future: expose `safe`/`finalized` via query param.

### Networks (nets)
- Mainnet only for this PoC. Testnets/L2s omitted; can be added with minor changes to RPC URL handling.

### Security
- No secrets in code. INFURA is passed via environment (`INFURA_PROJECT_ID` or `INFURA_URL`).
- Container runs with `python:3.12-slim` base which keeps image minimal. In production, run as non-root and read-only filesystem (can be tightened further).

### Observability
- Structured logging via FastAPI/Uvicorn. Extend with OpenTelemetry if needed.

### Deployment
- Container built by Dockerfile. Terraform provisions ECS Fargate, ALB, SGs, and a service with two tasks for HA in multiple AZs. ALB DNS is exported.

### CI/CD
- GitHub Actions builds the image on push.

---

## C4 Diagram (System + Container)

```mermaid
%% C4-ish diagram using Mermaid
flowchart TB
  user["User / Client"]
  lb["AWS ALB (HTTP)"]
  svc["ECS Service (Fargate)\nBalance API (Node.js)"]
  prov["Infura Ethereum RPC\n(mainnet/sepolia/holesky)"]

  user --> lb --> svc --> prov
```

If you prefer D2 ("dolphin") syntax:

```d2
User: Client
ALB: AWS ALB
API: ECS Fargate Service\nBalance API (Node.js)
Infura: Ethereum RPC (mainnet/sepolia/holesky)

User -> ALB -> API -> Infura
```

---

## Follow-up Questions and Answers

### How can we make this deployment secure from bad actors?
- Private subnets for tasks, ALB in public subnets; SGs least privilege.
- AWS WAF on ALB; rate limiting and IP reputation lists.
- OIDC for CI → AWS (no long-lived keys), store secrets in AWS Secrets Manager + KMS.
- Image scanning (Grype/Trivy), SBOM and image signing (Cosign), minimal base image.
- Input validation (EIP-55), strict timeouts, retry with backoff, circuit breaker on provider failures.

### Is this deployment HA? How to improve HA?
- ECS service runs 2+ tasks across AZs behind an ALB. Health checks and autoscaling can be added.
- Improve: multi-AZ ALB, desired_count >= 2, target tracking on CPU/RPS, multi-region with Route53 failover.

### How can we deploy changes 100+ times a day?
- Trunk-based development, small PRs, fast CI, canary or blue/green deployments with automatic rollback.
- Infra as code with policy checks (Checkov), protected main with required checks, preview envs.

### How would you scale to thousands of customers per minute?
- Horizontal scaling via ECS autoscaling; enable keep-alive and connection pooling.
- Add Redis/ElastiCache cache for hot addresses; set bounded TTL to reduce provider calls.
- Multi-provider abstraction with health scoring and failover.

### How would you monitor outages? What do alerts integrate with?
- Metrics: request rate, latency p50/p95/p99, error rates, provider error codes, cache hit rate.
- Tracing with OpenTelemetry → X-Ray/OTel backend.
- Dashboards and SLOs; alert to PagerDuty/Slack on burn-rate/error spikes and ALB 5xx.

---

## Local Development
```bash
# Install uv (if not installed): pip install uv
uv venv
. .venv/bin/activate
uv pip install -e .
export INFURA_PROJECT_ID=xxxx
uv run uvicorn src.app:app --reload --port 3000
curl "http://localhost:3000/address/balance/0xc94770007dda54cF92009BFF0dE90c06F603a09f"
```

## Docker
```bash
docker build -t balance-api:local .
docker run -e INFURA_PROJECT_ID=xxxx -p 3000:3000 balance-api:local
```

## Terraform (ECS Fargate)
```bash
cd terraform
terraform init
terraform apply -var="aws_region=us-west-2" -var="container_image=docker.io/<you>/balance-api:latest" -var="infura_project_id=xxxx"
```


