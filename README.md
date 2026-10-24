# TaskFlow: Two-Service ECS Learning Project

TaskFlow is a small, production-minded learning project designed to
teach AWS ECS through hands-on implementation. It contains two
independently deployable backend services that communicate over a
private network.

The goal is not to build a large product. The goal is to understand
container deployment, ECS services and task definitions, service
discovery, networking, health checks, observability, and failure
handling by building and operating a working system.

## 1. Project Goals

By completing this project, you should be able to:

-   Build and run multiple containerized services locally.
-   Package images and push them to Amazon ECR.
-   Deploy two independent services to Amazon ECS on AWS Fargate.
-   Make one ECS service call another over private networking.
-   Understand task definitions, clusters, services, desired count,
    health checks, and deployments.
-   Configure AWS Cloud Map service discovery.
-   Use security groups to restrict service-to-service traffic.
-   Use an Application Load Balancer (ALB) to expose only the public
    API.
-   Inspect logs and diagnose failures with Amazon CloudWatch.
-   Practise safe deployments, timeouts, retries, and independent
    service scaling.
-   Document cost controls and clean up AWS resources after experiments.

## 2. Scope

### In scope

-   Two Python/FastAPI services.
-   Local development with Docker Compose.
-   Separate container images and ECR repositories (or clearly separated
    image tags if justified).
-   ECS Fargate cluster with two ECS services.
-   Private HTTP communication from the API service to the processor
    service.
-   AWS Cloud Map private service discovery.
-   ALB in front of the public API service.
-   PostgreSQL persistence for job records; initially, only the API
    service accesses the database.
-   Structured application logs and health endpoints.
-   Automated unit and integration tests.
-   Infrastructure-as-code introduced after the first manual deployment
    is understood.
-   A deployment and troubleshooting runbook.

### Explicitly out of scope for the first version

-   Kubernetes/EKS.
-   Service mesh.
-   Authentication and multi-tenant user management.
-   Frontend UI.
-   Complex distributed transactions.
-   Kafka or multiple queues.
-   Automatic subscription or billing integrations.
-   Production-grade multi-region deployment.
-   SQS-based asynchronous processing until the synchronous
    service-to-service flow works reliably.

## 3. Architecture

``` text
                         Internet / Client
                                |
                                v
                    Application Load Balancer
                                |
                                v
                 ECS Service A: Task API (Fargate)
                     |                     |
                     | private HTTP        | database connection
                     v                     v
             AWS Cloud Map            PostgreSQL / RDS
             private DNS
                     |
                     v
             ECS Service B: Job Processor
                     |
                     v
              Result returned to API

        ECR: stores both container images
        CloudWatch: logs, metrics, alarms
        Security groups: restrict allowed network paths
```

The Task API is the only public application entry point. The Job
Processor must not be directly exposed to the internet. The API
discovers the processor through a private DNS name registered with AWS
Cloud Map. Security groups restrict processor inbound traffic to the API
service's security group.

For the initial learning deployment, use a cost-conscious setup and
choose networking deliberately. A private subnet without outbound
internet access can prevent image pulls, log delivery, or external URL
checks unless the required VPC endpoints or NAT connectivity are
configured. Document the selected design rather than adding expensive
networking components by default.

## 4. Services

### Service A: Task API

**Technology:** Python, FastAPI, PostgreSQL client/ORM, HTTP client.

Responsibilities:

-   Accept and validate job requests.
-   Create a job record with a unique ID and initial status.
-   Call the Job Processor through its private service-discovery DNS
    name.
-   Apply connection and response timeouts.
-   Handle processor errors without leaking internal details.
-   Save the result and final status in PostgreSQL.
-   Return a useful response to the client.
-   Emit structured logs with a request ID and job ID where available.

Suggested endpoints:

  -----------------------------------------------------------------------
  Method                  Endpoint                Purpose
  ----------------------- ----------------------- -----------------------
  `POST`                  `/jobs`                 Submit a URL-check job

  `GET`                   `/jobs/{job_id}`        Retrieve status and
                                                  result

  `GET`                   `/jobs`                 List recent jobs, with
                                                  pagination

  `GET`                   `/health`               Liveness check

  `GET`                   `/ready`                Readiness check,
                                                  including required
                                                  dependency checks where
                                                  appropriate
  -----------------------------------------------------------------------

Example request:

``` json
{
  "urls": [
    "https://example.com",
    "https://www.python.org"
  ]
}
```

Example response shape:

``` json
{
  "job_id": "generated-id",
  "status": "COMPLETED",
  "result": {
    "total": 2,
    "successful": 2,
    "failed": 0
  }
}
```

The exact response schema should be defined and tested during
implementation. Do not promise a successful result if the processor call
or persistence operation fails.

### Service B: Job Processor

**Technology:** Python, FastAPI, HTTP client for checking URLs.

Responsibilities:

-   Expose an internal processing endpoint.
-   Validate incoming payloads independently.
-   Check URLs with strict per-request timeouts and sensible limits.
-   Return a structured summary.
-   Return appropriate HTTP errors for invalid requests or processing
    failures.
-   Emit logs that can be correlated with the API request.
-   Expose a health endpoint.

Suggested endpoints:

  Method   Endpoint     Purpose
  -------- ------------ ---------------------------------------------
  `POST`   `/process`   Process a list of URLs and return a summary
  `GET`    `/health`    Liveness check

For local tests, support deterministic mocked processing so tests do not
depend on external websites. Limit the number of URLs and request
duration. Prevent arbitrary URL checking from becoming an unrestricted
SSRF-capable service: validate schemes, block
loopback/private/link-local and metadata-service destinations, and
account for redirects and DNS rebinding. Never use real external
requests as the only test strategy.

### Database

Use PostgreSQL for job records. The API service owns persistence in the
initial design; the processor does not need database credentials or
database network access.

Suggested fields:

-   `id`
-   `status` (`PENDING`, `PROCESSING`, `COMPLETED`, `FAILED`)
-   `input_payload` or a suitable normalized representation
-   `result_payload`
-   `error_code` (avoid storing secrets or sensitive response bodies)
-   `created_at`
-   `updated_at`

Because the first version uses synchronous HTTP, a request can take
time. Set explicit timeouts and document that this version is a learning
workflow, not a robust long-running job platform. A later SQS milestone
can turn it into asynchronous processing.

## 5. Local Development

This increment includes both FastAPI services, local Docker Compose,
PostgreSQL job storage, and a synchronous API-to-processor job flow.
AWS deployment is still planned.

Copy `.env.example` to `.env` if you want local overrides. Do not commit
`.env`. Images do not copy `.env` files; Compose injects environment
variables at runtime.

Example configuration names:

-   `PROCESSOR_BASE_URL`
-   `DATABASE_URL`
-   `LOG_LEVEL`
-   `PROCESSOR_TIMEOUT_SECONDS`
-   `MAX_URLS_PER_JOB`
-   `URL_TIMEOUT_SECONDS`

### Docker Compose (recommended)

Compose puts both containers on a private `taskflow` network. The Task
API is told to reach the processor at `http://job-processor:8001`. That
Compose DNS name is the local stand-in for AWS Cloud Map later.

``` bash
docker compose up --build
```

Health checks:

``` bash
curl http://localhost:8000/health
curl http://localhost:8000/ready
curl http://localhost:8001/health
```

Submit a job (the processor fetches each URL with timeouts and SSRF
checks; unit tests mock those fetches):

``` bash
curl -sS http://localhost:8000/jobs \
  -H 'Content-Type: application/json' \
  -d '{"urls":["https://example.com"]}'
```

`GET /jobs/{job_id}` and `GET /jobs` read records from PostgreSQL. The
API owns the database; the processor does not receive `DATABASE_URL`.

This first version waits for the processor over HTTP before responding.
That is intentional for learning service discovery. Long-running jobs
would normally use a queue later.

Port 8001 is published to your machine only so you can debug locally.
On ECS the processor will not have public ingress. Postgres port 5432 is
published for local debugging only and must not be opened to the
internet in AWS.

Stop and remove the containers:

``` bash
docker compose down
```

Build a single image without Compose:

``` bash
docker build -t taskflow-task-api ./services/task-api
docker build -t taskflow-job-processor ./services/job-processor
```

### Run with Python (no Docker)

Task API (port 8000):

``` bash
cd services/task-api
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
uvicorn app.main:app --reload --port 8000
```

Job Processor (port 8001):

``` bash
cd services/job-processor
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
uvicorn app.main:app --reload --port 8001
```

### Tests

``` bash
cd services/task-api && python -m pytest
cd services/job-processor && python -m pytest
```

### Planned: AWS deployment

The local job flow is implemented. Remaining work is ECR, ECS, Cloud
Map, the ALB, and operations practice.

## 6. AWS Deployment Milestones

### Milestone 1: Container basics

-   Build both services and Docker images.
-   Run locally and verify endpoints.
-   Add unit tests and Docker health checks where useful.
-   Push images to ECR.
-   Record image tags and build steps in the README.

**Exit criteria:** Both services run locally in containers and tests
pass.

### Milestone 2: First ECS service

-   Create an ECS cluster using Fargate.
-   Create a task definition for the Task API.
-   Configure CPU, memory, container port, environment variables,
    logging, task execution role, and task role as appropriate.
-   Deploy one task and inspect startup logs.
-   Verify task health and understand stopped-task reasons.

**Exit criteria:** The API starts on ECS and logs are visible in
CloudWatch.

### Milestone 3: Second ECS service and private communication

-   Create the processor task definition and ECS service.
-   Configure AWS Cloud Map private DNS service discovery.
-   Configure security groups so the processor accepts traffic only from
    the API service on its application port.
-   Configure the API's processor base URL using the private DNS name.
-   Test successful requests and processor failures.
-   Confirm the processor has no public ingress.

**Exit criteria:** API-to-processor HTTP calls work over private
networking and direct internet access to the processor is not available.

### Milestone 4: ALB and health checks

-   Place an ALB in front of the Task API.
-   Configure listener, target group, container port mapping, and
    health-check path.
-   Verify that the ALB routes only to healthy API tasks.
-   Stop an API task and observe ECS service replacement.
-   Test a bad health-check path and diagnose the outcome.

**Exit criteria:** The API is reachable through the ALB, and the
processor remains internal.

### Milestone 5: Reliability and observability

-   Add explicit HTTP timeouts.
-   Add bounded retries only for operations where retrying is safe.
-   Ensure the API does not create misleading successful job records on
    processor failure.
-   Add structured logs and correlation IDs.
-   Add CloudWatch metrics/alarms that are meaningful for the project.
-   Test a processor crash, slow response, invalid request, and database
    failure.

**Exit criteria:** Failure behaviour is documented and diagnosable from
logs and API responses.

### Milestone 6: Scaling and deployments

-   Scale API and processor services independently.
-   Test what happens when the processor has fewer tasks than the API.
-   Perform a rolling deployment of each service separately.
-   Test a broken image or failed health check in a controlled way.
-   Document rollback to a previously working task-definition
    revision/image tag.
-   Add CI/CD after the manual process is understood.

**Exit criteria:** Each service can be deployed and scaled
independently, and rollback instructions are tested.

### Milestone 7: Infrastructure as code

Once the manual resources are understood, use Terraform or AWS CDK to
define the resources. Prefer one infrastructure tool rather than mixing
tools.

Include a plan/review step before applying changes. Avoid hard-coded
account IDs, credentials, or region assumptions. Document resource
destruction and verify that persistent data is handled intentionally.

**Exit criteria:** A developer can recreate the learning environment
from documented configuration and safely tear it down.

## 7. ECS Concepts to Demonstrate

-   Cluster versus task versus service.
-   Task definition revisions.
-   Desired count and service scheduler behaviour.
-   Fargate CPU and memory sizing.
-   Container port mapping and task networking.
-   Task execution role versus task role.
-   ALB listener, target group, and health checks.
-   Cloud Map namespace, service registration, and private DNS.
-   Security group source rules and least-privilege networking.
-   CloudWatch log groups, log streams, metrics, and alarms.
-   Rolling deployments and rollback.
-   Independent service scaling.
-   Stopped task reasons and common image-pull/startup failures.

## 8. Test Plan

### Unit tests

-   Payload validation.
-   URL validation and limits.
-   Result aggregation.
-   Status transitions.
-   Error mapping.

### Integration tests

-   API-to-processor success path.
-   Processor returns a controlled error.
-   Processor is unreachable.
-   Processor times out.
-   Database is unavailable.
-   Job result is saved and retrievable.

### AWS operational tests

-   ECS replaces a stopped task.
-   ALB stops routing to an unhealthy task.
-   API resolves the processor private DNS name.
-   Processor ingress rejects traffic from an unauthorized source.
-   CloudWatch contains logs from both services.
-   One service can be redeployed without rebuilding the other.
-   Rollback procedure restores a known-good revision.

Use mocked HTTP calls for deterministic CI tests. Avoid tests that
depend on arbitrary public URLs being available.

## 9. Security and Cost Guardrails

-   Do not commit credentials or `.env` files.
-   Use IAM roles rather than embedding AWS access keys in containers.
-   Keep the processor private.
-   Restrict security-group ingress to necessary sources and ports.
-   Validate URL input to reduce SSRF risk.
-   Use HTTPS for the public ALB when configuring a real public
    deployment.
-   Do not expose database ports to the internet.
-   Avoid logging secrets, full environment variables, or sensitive
    payloads.
-   Set AWS budgets or billing alerts before experimenting.
-   Stop or delete resources after practice.
-   Remember that ALBs, NAT Gateways, RDS, public IPv4 addresses, and
    CloudWatch usage may incur charges.
-   Confirm actual regional pricing and account eligibility before
    relying on free-tier allowances.

## 10. Definition of Done

The project is complete when:

-   [x] Both services run locally in containers.
-   [x] Automated tests cover success and failure paths.
-   [ ] Both images are stored in ECR.
-   [ ] Both services run as separate ECS Fargate services.
-   [ ] Service A calls Service B through private service discovery.
-   [ ] Only the Task API is exposed through the ALB.
-   [ ] Security groups restrict service-to-service traffic.
-   [x] Job records and results persist in PostgreSQL.
-   [ ] Logs from both services are available in CloudWatch.
-   [ ] Task failure, health checks, deployment, scaling, and rollback
    have been tested.
-   [ ] README includes architecture, deployment steps, troubleshooting,
    cost notes, and cleanup steps.
-   [ ] No secrets or generated cloud credentials are committed.

## 11. Suggested Repository Layout

``` text
taskflow/
├── services/
│   ├── task-api/
│   │   ├── app/
│   │   ├── tests/
│   │   ├── Dockerfile
│   │   └── requirements.txt
│   └── job-processor/
│       ├── app/
│       ├── tests/
│       ├── Dockerfile
│       └── requirements.txt
├── tests/
│   └── integration/
├── infra/
│   └── terraform/       # Add after manual ECS learning
├── docker-compose.yml
├── .env.example
├── .gitignore
├── README.md
└── AGENTS.md
```

The implementation agent may adjust this structure if there is a
concrete reason, but should explain the trade-off and obtain approval
before making major structural changes.

## 12. Learning Rule

Build in small increments. After each milestone, explain the AWS
resources created, why they are needed, how traffic flows, how failures
are detected, and how to clean up. Prefer a working, observable
two-service system over adding more AWS services prematurely.
