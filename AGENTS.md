# AGENTS.md --- TaskFlow Project Instructions

This file defines how coding agents should work on TaskFlow. Read it
before inspecting or changing the repository.

## 1. Mission

Build TaskFlow as a small, understandable learning project for AWS ECS.
The project contains two independently deployable Python/FastAPI
services:

1.  **Task API** --- public-facing API that validates requests, stores
    job records in PostgreSQL, and calls the processor service.
2.  **Job Processor** --- internal service that validates and processes
    a bounded list of URLs and returns a structured result.

The learning objectives are ECS Fargate, ECR, task definitions,
services, private service discovery, networking/security groups, ALB
health checks, CloudWatch, scaling, deployments, and failure handling.

Do not turn this into an unnecessarily complex production platform. Keep
business logic deliberately small so infrastructure and operations
remain the main learning focus.

## 2. Agent Operating Rules

-   Start by inspecting the repository. Do not assume it is empty.
-   Before editing, report the current state, proposed changes, files
    affected, commands/tests to run, and any AWS resources that would be
    created or changed.
-   Work in small, reviewable milestones. The user wants to approve each
    meaningful change.
-   **Do not proceed to the next milestone until the user approves the
    current milestone.**
-   Do not deploy to AWS, create billable resources, modify cloud
    infrastructure, or destroy resources without explicit approval for
    that specific action.
-   Do not run `terraform apply`, `terraform destroy`, `cdk deploy`, AWS
    resource creation commands, or equivalent deployment operations
    without explicit approval.
-   Local-only operations such as inspecting files, writing code,
    running tests, and building local containers are permitted within
    the approved milestone.
-   If the repository already has a convention or tool, inspect and
    follow it rather than replacing it without reason.
-   Prefer simple, explicit code and explain decisions in
    learner-friendly language.
-   Do not claim a test passed unless it was actually run and its result
    was observed.
-   If a command cannot be run, state why and provide the exact command
    the user can run.
-   Do not invent AWS account IDs, resource ARNs, regions, DNS names,
    credentials, or deployment results.
-   Never print, commit, or copy secrets. Do not read or display
    credential files. Use placeholders in examples.
-   Do not change unrelated files or perform broad refactors without
    approval.

## 3. Approval Protocol

For every milestone, use this process:

1.  **Inspect:** review relevant source, configuration, tests, and
    repository conventions.
2.  **Plan:** propose a small set of changes and explain why.
3.  **Wait:** request approval before editing if the change is a
    meaningful implementation milestone.
4.  **Implement:** make only the approved changes.
5.  **Verify:** run relevant tests, linting, formatting, and local
    checks where available.
6.  **Report:** list files changed, commands run, results, remaining
    issues, and the next proposed milestone.
7.  **Wait again:** do not begin the next milestone until the user
    approves it.

For small mechanical changes inside an already approved milestone,
proceed without asking for approval after every individual line.

## 4. Technology and Architecture

Preferred stack:

-   Python with FastAPI for both services.
-   Docker for containerization.
-   Docker Compose for local development.
-   Amazon ECR for images.
-   Amazon ECS on AWS Fargate for compute.
-   AWS Cloud Map for private service discovery.
-   Application Load Balancer for the Task API only.
-   PostgreSQL for job records, initially accessed only by the Task API.
-   Amazon CloudWatch for logs, metrics, and alarms.
-   Terraform for infrastructure as code only after the user understands
    and approves the initial manual deployment.

Do not add a frontend, Kubernetes, service mesh, Kafka, Redis, or extra
services unless the user explicitly approves a new scope.

### Service communication

-   Locally, Task API calls the processor through its Docker Compose
    service name.
-   On ECS, Task API calls the processor through a private Cloud Map DNS
    name.
-   The processor must not have public ingress.
-   Security groups must allow processor traffic only from the Task API
    service security group on the required application port.
-   The public ALB routes to the Task API, not the processor.
-   Configure service URLs through environment variables; never
    hard-code environment-specific DNS names in application code.

### Database ownership

-   The Task API owns job persistence.
-   The processor must not access PostgreSQL in the initial design.
-   Do not add a database dependency to the processor merely for
    convenience.
-   Keep database migrations explicit and testable.

### Synchronous first, asynchronous later

-   Start with synchronous HTTP communication from Task API to Job
    Processor.
-   Add bounded timeouts and clear error handling.
-   Do not introduce SQS until the two-service ECS flow works and the
    user approves the asynchronous-processing milestone.
-   Explain that synchronous HTTP is intentionally used to learn
    networking and service discovery, and that long-running jobs would
    usually benefit from asynchronous processing.

## 5. Security Requirements

-   Never commit AWS credentials, database passwords, API keys, tokens,
    or real `.env` files.
-   Maintain `.env.example` with placeholders only.
-   Use ECS task execution roles for image pulls/log delivery and task
    roles for application AWS API permissions; do not conflate the two.
-   Follow least privilege for IAM.
-   Do not make PostgreSQL publicly accessible.
-   Keep Job Processor private.
-   Do not expose all container ports or open ingress to `0.0.0.0/0` as
    a shortcut.
-   Validate URL inputs and permit only expected URL schemes.
-   Protect against SSRF: block loopback, private, link-local, and cloud
    metadata destinations; account for redirects and DNS resolution
    changes; apply request limits and timeouts.
-   Do not log secrets, all environment variables, or sensitive response
    content.
-   Use safe error responses; do not leak stack traces to clients in
    deployed environments.
-   Do not perform external URL requests in ordinary unit tests; mock
    them or use a controlled test server.
-   Before suggesting public exposure, explain TLS and the
    security-group implications.

## 6. Reliability Requirements

-   Add explicit connection and response timeouts to service-to-service
    HTTP calls.
-   Retries must be bounded and used only where retrying is safe. Avoid
    blind retries of non-idempotent operations.
-   Return appropriate HTTP status codes and stable error response
    shapes.
-   Do not mark a job `COMPLETED` if processing or required persistence
    fails.
-   Ensure job status transitions are clear and covered by tests.
-   Include correlation/request IDs in logs where practical.
-   Keep health checks lightweight. Distinguish liveness from readiness
    where the deployment design needs both.
-   Configure ECS and ALB health checks intentionally and document the
    selected paths and expected status codes.
-   Avoid doing slow processing inside a health-check request.
-   Handle processor unavailability and database failure without
    crashing the API process.

## 7. Coding Standards

-   Use type hints for public functions and important data structures.
-   Keep modules small and responsibilities clear.
-   Use Pydantic models for API request and response validation.
-   Keep configuration in one documented settings layer.
-   Pin or constrain dependencies appropriately and explain dependency
    changes.
-   Use structured logging where practical.
-   Add tests for new behaviour and failure paths.
-   Keep tests deterministic; mock HTTP, clock, and external
    dependencies where appropriate.
-   Do not add abstraction layers without a concrete use case.
-   Use consistent formatting and linting if configured in the
    repository; do not introduce multiple overlapping tools without
    reason.
-   Make Docker images reproducible and avoid copying `.env` or local
    credentials into images.
-   Use a non-root container user where practical.
-   Handle SIGTERM gracefully where relevant to ECS task shutdown.
-   Keep the README accurate to the implemented state. Mark
    unimplemented AWS deployment steps as planned, not completed.

## 8. Milestones and Expected Approval Gates

### Milestone 0 --- Repository reconnaissance

No feature implementation.

-   Inspect files, Git status, project conventions, existing tests, and
    available tooling.
-   Identify whether the repository is empty or already contains work.
-   Propose a final folder layout and short milestone plan.
-   Identify assumptions and any decisions needing user input.
-   Do not create AWS resources.

**Deliverable:** a concise reconnaissance report and proposed plan. Wait
for approval.

### Milestone 1 --- Local skeleton

-   Create the Task API and Job Processor application skeletons.
-   Add health endpoints, configuration, dependency manifests, and
    minimal tests.
-   Add Dockerfiles and Docker Compose.
-   Add `.gitignore` and `.env.example`.
-   Do not implement AWS infrastructure yet.

**Acceptance:** both services build and run locally; health endpoints
and tests pass.

### Milestone 2 --- Service-to-service flow

-   Implement the job request and response models.
-   Task API validates a request and calls the processor over HTTP.
-   Processor validates and processes a bounded URL list.
-   Add timeouts, error mapping, URL safety validation, and
    deterministic tests.
-   Add PostgreSQL persistence for the Task API and a migration
    strategy.
-   Add integration tests for success, timeout, processor unavailable,
    and persistence errors.

**Acceptance:** end-to-end local flow works and failure paths are
tested.

### Milestone 3 --- Local developer experience

-   Complete Docker Compose dependencies and service networking.
-   Document build, run, test, and debug commands.
-   Confirm secrets are not copied into images or committed.
-   Verify a fresh local setup from the README.

**Acceptance:** a developer can start the application from documented
steps.

### Milestone 4 --- ECR and first ECS task

-   Prepare image build/tag/push instructions.
-   Explain the task definition, execution role, task role, logging,
    port mappings, CPU, and memory.
-   Create deployment configuration or infrastructure definitions only
    after approval.
-   Do not deploy or create billable resources without explicit
    approval.

**Acceptance:** approved deployment steps are documented and/or executed
only with permission.

### Milestone 5 --- Private service discovery

-   Define Cloud Map private namespace/service configuration.
-   Configure ECS processor service and API environment variables.
-   Define least-privilege security-group rules.
-   Document DNS resolution and connectivity troubleshooting.
-   Keep processor private.

**Acceptance:** Task API can reach the processor through private DNS;
unauthorized inbound paths are blocked.

### Milestone 6 --- ALB, health checks, and operations

-   Configure the ALB and target group for Task API only.
-   Configure health checks and CloudWatch logs.
-   Document task replacement, stopped-task inspection, and common
    failures.
-   Add controlled failure experiments.

**Acceptance:** public API access works through the ALB, processor stays
private, and failures are observable.

### Milestone 7 --- Scaling and deployment practice

-   Configure independent desired counts and scaling policies.
-   Test rolling deployments and rollback in an approved environment.
-   Add CI/CD only after manual deployment is understood.
-   Add alarms where they provide a clear learning outcome.

**Acceptance:** each service can be deployed and scaled independently
and rollback is documented/tested.

### Milestone 8 --- Infrastructure as code

-   Introduce one IaC tool, preferably Terraform.
-   Review plans before changes.
-   Keep state handling and secrets secure.
-   Provide explicit cost and destruction guidance.
-   Never apply or destroy resources without approval.

**Acceptance:** infrastructure can be recreated from reviewed
configuration and safely torn down.

### Optional Milestone 9 --- SQS

Only after the synchronous version works and the user approves:

-   Introduce SQS and a dead-letter queue.
-   Change job submission to return a job ID quickly.
-   Have a worker consume messages and update job state.
-   Add idempotency, visibility timeout, retry, and duplicate-message
    handling.
-   Compare synchronous HTTP with asynchronous queue-based processing.

## 9. Testing and Verification

Before declaring a milestone complete:

-   Run the relevant unit tests.
-   Run integration tests when dependencies are available.
-   Run formatting/linting if configured.
-   Build affected Docker images when feasible.
-   Review `git diff` for unrelated changes, secrets, and generated
    files.
-   State exact commands and observed outcomes.
-   If AWS tests require credentials or billable resources, do not
    attempt them without permission.

Never claim an AWS deployment or cloud behaviour has been verified based
only on code inspection.

## 10. Documentation Requirements

Keep the README updated with:

-   Project purpose and scope.
-   Architecture diagram.
-   Local setup and test commands.
-   Environment-variable reference.
-   API examples.
-   Container build commands.
-   ECR/ECS deployment steps.
-   Service-discovery and security-group explanation.
-   Health-check and CloudWatch guidance.
-   Troubleshooting procedures.
-   Cost warnings and cleanup steps.
-   Clear distinction between completed and planned capabilities.

Prefer explaining the reason behind each AWS resource, not merely
listing console clicks.

## 11. Completion Report Format

At the end of every approved milestone, report:

1.  **Implemented:** concise list.
2.  **Files changed:** paths and purpose.
3.  **Verification:** commands run and actual results.
4.  **AWS impact:** resources created/changed, or "none".
5.  **Known limitations:** what remains.
6.  **Learning notes:** ECS/backend concepts demonstrated.
7.  **Next proposal:** the next milestone and what approval is needed.

Then stop and wait for the user's decision.
