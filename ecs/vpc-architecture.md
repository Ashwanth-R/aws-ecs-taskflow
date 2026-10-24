# TaskFlow VPC Architecture

**Design:** ALB public · ECS + RDS private · NAT Gateway for outbound

---

## Diagram

```mermaid
flowchart TD
    Internet(["🌐 Internet\nClient / browser"])

    IGW["Internet Gateway\nRoutes public IP ↔ private VPC IP"]

    subgraph VPC["VPC — 10.0.0.0/16"]
        subgraph Public["🔵 Public Subnets  (10.0.0.0/24 · 10.0.1.0/24)"]
            ALB["Application Load Balancer\nPorts 80 / 443 · public IP\nspans 2 Availability Zones"]
            NAT["NAT Gateway\nOutbound-only · elastic IP\n⚠ ~$32/month"]
        end

        subgraph Private["🟢 Private Subnets  (10.0.10.0/24 · 10.0.11.0/24)"]
            API["Task API\nECS Fargate · port 8000\nprivate IP only"]
            PROC["Job Processor\nECS Fargate · port 8001\nno internet exposure"]
            RDS[("PostgreSQL\nport 5432\nprivate only")]
        end
    end

    Internet  -->|HTTPS / HTTP|         IGW
    IGW       -->|inbound|              ALB
    ALB       -->|:8000  alb-sg → task-api-sg|   API
    API       -->|:8001  task-api-sg → processor-sg| PROC
    API       -->|:5432  task-api-sg → rds-sg|    RDS

    API       -. "ECR pulls · SSM · CloudWatch Logs" .-> NAT
    PROC      -. "ECR pulls · URL checks" .->         NAT
    NAT       -. outbound .->                          IGW
    IGW       -. outbound .->                          Internet
```

> **Tip — view in VS Code:** install the [Markdown Preview Mermaid Support](https://marketplace.visualstudio.com/items?itemName=bierner.markdown-mermaid) extension, then open this file and press `Cmd+Shift+V`.
> On GitHub the diagram renders automatically.

---

## How a request travels

1. **Client → IGW → ALB.** The ALB is the only resource with a public IP. Your ECS tasks have private IPs only and are unreachable from the internet directly.

2. **ALB → Task API (port 8000).** The ALB forwards to a healthy Task API task using its private IP. Even though the ALB is in the public subnet, its *target* is in the private subnet — this is intentional and normal.

3. **Task API → Job Processor (port 8001).** Task API calls the processor over a private Cloud Map DNS name (`processor.taskflow.local`). This never leaves the VPC. The Job Processor has no public IP.

4. **Task API → PostgreSQL (port 5432).** Database connection, private subnet only. Job Processor never touches PostgreSQL — no credentials, no security group rule.

5. **ECS tasks → NAT Gateway → Internet (outbound only).** ECS containers pull their images from ECR and write logs to CloudWatch at startup. The Job Processor also needs outbound internet for URL checks. NAT Gateway is a one-way door: private resources can initiate outbound connections; nothing on the internet can initiate inbound connections back through it.

---

## Security groups

Security groups reference each other as sources rather than IP ranges. When a new ECS task starts with a new private IP, rules that say "from `task-api-sg`" automatically cover it.

| Security group   | Direction | Port | Source / Destination | Reason |
|-----------------|-----------|------|----------------------|--------|
| `alb-sg`        | IN        | 443  | `0.0.0.0/0`          | Public HTTPS |
| `alb-sg`        | IN        | 80   | `0.0.0.0/0`          | Redirect to 443 |
| `alb-sg`        | OUT       | 8000 | `task-api-sg`        | Forward to Task API |
| `task-api-sg`   | IN        | 8000 | `alb-sg`             | Only ALB can reach it |
| `task-api-sg`   | OUT       | 8001 | `processor-sg`       | Call processor |
| `task-api-sg`   | OUT       | 5432 | `rds-sg`             | Database |
| `task-api-sg`   | OUT       | 443  | `0.0.0.0/0`          | ECR / SSM / CloudWatch |
| `processor-sg`  | IN        | 8001 | `task-api-sg`        | Only Task API can reach it |
| `processor-sg`  | OUT       | 443  | `0.0.0.0/0`          | ECR pulls + URL checking |
| `rds-sg`        | IN        | 5432 | `task-api-sg`        | Only Task API has credentials |

---

## Subnet CIDR plan

ALBs require at least two Availability Zones, so we always create two public and two private subnets.

| Name       | CIDR           | AZ           | Contains |
|------------|----------------|--------------|----------|
| `public-a` | 10.0.0.0/24   | us-east-1a   | ALB node, NAT Gateway |
| `public-b` | 10.0.1.0/24   | us-east-1b   | ALB node (ALB requires 2 AZs) |
| `private-a`| 10.0.10.0/24  | us-east-1a   | ECS tasks, RDS primary |
| `private-b`| 10.0.11.0/24  | us-east-1b   | ECS tasks (scaled), RDS standby |

---

## NAT Gateway — cost and alternatives

> **⚠ NAT Gateway costs ~$32/month ($1.08/day) even with zero traffic.**
> Delete it at the end of each learning session:
> ```bash
> aws ec2 delete-nat-gateway --nat-gateway-id <id> --region us-east-1
> ```
> You can recreate it in under a minute when you resume.

| Option | Cost | Notes |
|--------|------|-------|
| **NAT Gateway** *(recommended for learning)* | ~$32/month | Single resource, works for all outbound traffic. Delete when not learning. |
| **VPC Interface Endpoints** | ~$7/month each (~$35 for 5 endpoints) | Covers ECR, S3, CloudWatch Logs, SSM. No per-GB AWS charge. Job Processor still needs NAT for external URL checks. Better for production at scale. |
