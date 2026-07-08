# DevOps Assessment: Terraform + Database Reliability

Terraform design for a standard `Internet → ALB → ECS/Fargate → RDS` stack on AWS,
plus a locally runnable PostgreSQL setup demonstrating migrations, seed data,
query optimization, and backup/restore.

Actual AWS deployment is **not** part of this submission — the Terraform is
validated via `fmt` / `init` / `validate` / `plan`, and the database tasks run
entirely locally via Docker Compose, as the assessment specifies.

## Repository layout

```
infra/
  modules/
    network/   # VPC, public + private subnets, IGW, NAT gateway, route tables
    ecs/       # ALB, security groups, ECS cluster, Fargate task + service
    rds/       # Private RDS instance + security group (ingress from ECS only)
  envs/
    dev/       # dev.tfvars: small instance, 3-day backups, deletion protection off
    prod/      # prod.tfvars: larger instance, 30-day backups, deletion protection on

.github/workflows/terraform.yml   # fmt/init/validate/plan on every PR touching infra/

db/
  migrations/001_create_tables.sql   # hotel_bookings + booking_events schema + index
  seed/002_seed_data.sql             # 120 seeded bookings across cities/orgs/statuses
  queries/target_query.sql           # the query from Part 5, for manual EXPLAIN ANALYZE

scripts/
  backup.sh    # timestamped pg_dump of the local database
  restore.sh   # restores a backup into a FRESH database and verifies row counts

docker-compose.yml   # local Postgres 15, auto-runs migrations + seed on first boot
```

## Part 1 & 2 — Terraform infrastructure

**Traffic flow:** `Internet → ALB (public subnets) → ECS/Fargate (private subnets) → RDS (private subnets)`

- `network` module creates a VPC with 2 public + 2 private subnets across two AZs,
  an Internet Gateway for the public subnets, and a single NAT Gateway so
  Fargate tasks in private subnets can still pull images / reach AWS APIs.
- `ecs` module creates the ALB (public, security group open on :80 to the
  internet), a target group/listener, an ECS cluster, and a Fargate service
  running in the **private** subnets with `assign_public_ip = false`. The
  ECS security group only accepts traffic from the ALB's security group —
  not from the internet directly.
- `rds` module creates a private RDS instance (`publicly_accessible = false`,
  hardcoded — not environment-dependent) with a security group that **only**
  allows inbound traffic from the ECS security group passed in as a variable.
  No CIDR-based ingress rule exists on this security group at all.

**Environment separation** (`envs/dev`, `envs/prod`) — each has its own:
- `variables.tf` with different defaults
- `<env>.tfvars` for instance sizing
- local backend state file (swap for an S3 + DynamoDB backend per environment
  in real usage — the commented-out block in each `main.tf` shows the shape)
- RDS backup retention and deletion protection:

| | dev | prod |
|---|---|---|
| DB instance class | db.t3.micro | db.t3.medium |
| Backup retention | 3 days | 30 days |
| Deletion protection | false | true |
| Multi-AZ | false | true |
| Desired task count | 1 | 2 |

### Validating the Terraform

```bash
cd infra/envs/dev
terraform fmt -check -recursive ../..
terraform init -backend=false
terraform validate
terraform plan -var-file=dev.tfvars -var="db_password=local-test-only" -refresh=false
```

Same commands work in `infra/envs/prod` with `prod.tfvars`. A real `plan`
against AWS requires valid credentials (`aws configure` or
`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` env vars) since Terraform's AWS
provider needs to authenticate even for a plan — that step is optional per
the assessment, so CI runs it in a best-effort, non-blocking way (see below).

### Part 3 — GitHub Actions

`.github/workflows/terraform.yml` runs on every PR that touches `infra/`, for
both `dev` and `prod` in parallel (matrix build):

1. `terraform fmt -check -recursive`
2. `terraform init -backend=false` (no real backend/credentials needed in CI)
3. `terraform validate`
4. `terraform plan` (using placeholder credentials/password — this step is
   allowed to fail gracefully since real AWS deployment isn't required; its
   output is still captured either way)
5. Plan output is uploaded as a **workflow artifact** and posted as a **PR
   comment** automatically.

## Part 4 & 5 — Local database

```bash
docker compose up -d
```

On first boot, Postgres automatically runs (in order):
1. `db/migrations/001_create_tables.sql` — creates `hotel_bookings` and
   `booking_events`, plus the index described below.
2. `db/seed/002_seed_data.sql` — inserts 120 bookings across 5 cities, 5
   organizations, and 4 statuses, with `created_at` timestamps spread across
   the last 45 days (relative to `now()`, so the "last 30 days" query below
   always has real matching rows, no matter when you run this).

> These only run the **first** time the `db_data` volume is created. If
> you've already started the stack before and want a clean re-seed:
> `docker compose down -v && docker compose up -d`

### Query optimization (Part 5)

Target query:

```sql
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

Index added in `001_create_tables.sql`:

```sql
CREATE INDEX idx_hotel_bookings_city_created_at
    ON hotel_bookings (city, created_at)
    INCLUDE (org_id, status, amount);
```

**Why this shape:** `city` is filtered by equality and `created_at` by a
range, so `city` leads the composite index and `created_at` follows it —
that's the standard "equality columns before range columns" rule for B-tree
indexes, and lets Postgres do an index range scan instead of a sequential
scan over the whole table. `org_id`, `status`, and `amount` are added as
`INCLUDE` columns (not part of the index key) purely so the query can be
answered as an **index-only scan** — Postgres never has to fetch the actual
table row (the heap) for the columns the `SELECT`/`GROUP BY` needs.

Verify the plan is actually using it:

```bash
docker compose exec db psql -U app_admin -d hotelbook \
  -c "EXPLAIN ANALYZE $(cat db/queries/target_query.sql)"
```

Look for `Index Only Scan using idx_hotel_bookings_city_created_at` in the
output rather than `Seq Scan on hotel_bookings`.

## Part 6 — Backup and restore

```bash
# Create a timestamped dump of the live database
./scripts/backup.sh
#   -> backups/hotelbook_backup_20260705_143000.sql

# Restore the most recent backup into a FRESH database
# (hotelbook_restore_test) — does not touch the live "hotelbook" DB
./scripts/restore.sh

# Or restore a specific file:
./scripts/restore.sh backups/hotelbook_backup_20260705_143000.sql
```

**How restore is verified:** `restore.sh` drops and recreates
`hotelbook_restore_test`, loads the dump into it, then runs row-count checks
against `hotel_bookings` and `booking_events` plus a check that the index
from the migration survived the dump/restore round-trip. It prints all three
counts and exits non-zero if the counts look wrong (e.g., zero rows), so a
failed restore is loud rather than silent.

Manual spot-check after restore:

```bash
docker compose exec db psql -U app_admin -d hotelbook_restore_test \
  -c "SELECT city, COUNT(*) FROM hotel_bookings GROUP BY city;"
```

## Design notes / trade-offs

- **NAT Gateway cost**: a single NAT Gateway is used (not one per AZ) to keep
  this demo cheap to actually run; a production setup would typically use one
  NAT Gateway per AZ for availability.
- **Container image**: the ECS task runs a placeholder `nginx` image since
  the assessment doesn't require a real backend — swap `container_image` in
  `variables.tf`/`tfvars` for a real ECR image URI when there's an actual app
  to deploy.
- **Secrets**: `db_password` is deliberately kept out of both `tfvars` files.
  `dev` has a throwaway default for convenience; `prod` has no default at all
  and must be supplied via `TF_VAR_db_password` (or, in a real environment,
  pulled from AWS Secrets Manager / SSM Parameter Store rather than passed as
  a Terraform variable at all).
