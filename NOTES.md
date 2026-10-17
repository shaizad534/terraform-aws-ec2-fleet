# Notes

## Which instance is protected from deletion

`db-01` (instance type `r5.xlarge`, root volume `io1` 200 GiB) is the instance
that carries `prevent_destroy = true`.

## Why `db-01`

- **Highest blast radius.** It is the fleet's data node. Losing it is the most
  disruptive failure in this group.
- **Stateful + expensive to rebuild.** Its root volume is a provisioned-IOPS
  `io1` volume (5000 IOPS). Recreating it means re-provisioning storage, data
  restore, and re-establishing access, not just relaunching a stateless app box.
- **Most costly mistake.** A stray `terraform destroy` or a refactor that drops
  the instance from state would silently delete production data. The other four
  instances are effectively stateless and cheap to recreate.

The guard is intentionally the smallest possible safety net: it stops the one
delete that actually hurts, without making routine `terraform destroy` require
editing code for the disposable instances.

## How the guard is implemented

`prevent_destroy` in Terraform must be a literal `true`/`false`; it cannot be a
computed expression. The module therefore splits the single `var.instances` map
into two `for_each` resource blocks:

- `aws_instance.this` — all instances with `protect = false`.
- `aws_instance.guarded` — instances with `protect = true`, which carry the
  `lifecycle { prevent_destroy = true }` block.

Everything is still driven by the one `instances` variable; only the lifecycle
attribute lives in a dedicated block. The guarded instance also sets
`disable_api_termination = true` for defense-in-depth at the AWS API level.

## Removing the guard (when you genuinely need to)

1. Set `protect = false` for `db-01` in `terraform.tfvars` and apply, then
2. `terraform state rm` the resource (or apply again) before destroying.

Because `prevent_destroy` is evaluated on the destroy plan, the flag must be
cleared and applied first.

---

# Task 3 — Multi-Account IAM & Cross-Account Access

## Task

**Account A (`000000000000`)**

1. `group1` — CLI/programmatic-only access. Members: `engine`, `ci`.
2. `group2` — full console + CLI access. Members: two named users.
3. `roleA` — administrative access to all AWS services except IAM.
4. `roleB` — only permission is to assume a role in Account B.

**Account B (`111111111111`)**

5. `roleC` — full access to a single named S3 bucket, assumable only by `roleB`
   from Account A — not by anything else in Account A.

---

## The five conditions explained

Two separate AWS accounts:

- **Account A** = `000000000000`
- **Account B** = `111111111111`

An **IAM role** is a temporary badge you put on to borrow certain powers.
**Assume a role** means putting on that temporary badge. An **S3 bucket** is a
storage box for files.

### Account A

#### 1) `group1` — CLI/programmatic-only team

**Task:** a group for CLI/programmatic-only access; members `engine`, `ci`.

**Explanation:** `group1` is an **IAM group** (a team — everyone in it gets the
same permissions). Its members, `engine` and `ci`, are automation/machines. They
receive **access keys** (permanent keys used by the **CLI** — the command line)
but **no console login** (no AWS website password). They can run scripts and
tools, but cannot sign in to the AWS website.

**Example policy** for CLI/programmatic-only access (no console sign-in):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyConsoleSignIn",
      "Effect": "Deny",
      "Action": [
        "signin:Authenticate",
        "signin:AuthorizeOAuth2Access",
        "signin:CreateOAuth2Token"
      ],
      "Resource": "*"
    }
  ]
}
```

No console password (login profile) is created for `engine`/`ci` — they use
access keys only.

The broad `ec2:*` (including VPC), `s3:*`, and `rds:*` allows have been removed.
Workload permissions are not specified by the task: `ci` uses the
least-privilege policy in **Task 4**, and `engine` should get its own
least-privilege policy.

#### 2) `group2` — full console + CLI team

**Task:** a group for full console + CLI access; two named users of your choice.

**Explanation:** `group2` is an **IAM group** for real people. Its two members
get **both** a **console login** (AWS website password) **and access keys**
(CLI/command-line keys). They can work from the website and from the command
line.

**Sample policy** (group permission policy — full console + CLI = full access):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "*", "Resource": "*" }
  ]
}
```

#### 3) `roleA` — administrator except IAM

**Task:** a role with administrative access to all AWS services except IAM.

**Explanation:** `roleA` is an **IAM role** (temporary badge) that can use every
AWS service — servers, storage, databases, and so on — **except IAM** (Identity
and Access Management, the security office that controls users, roles, and
permissions). It can run the platform but cannot change who has access or alter
permissions.

**Sample policy** (permission policy — allow everything, deny IAM):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "*", "Resource": "*" },
    { "Effect": "Deny", "Action": "iam:*", "Resource": "*" }
  ]
}
```

Trust policy: not specified by the task.

#### 4) `roleB` — assume-role-only pass

**Task:** a role whose only permission is to assume a role in Account B.

**Explanation:** `roleB` is an **IAM role** with exactly one permission:
**assume a role** (put on the temporary badge) in Account B. It has no other
powers — no storage, no servers, no other roles.

**Sample policy** (permission policy — only assume `roleC` in Account B):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::111111111111:role/roleC"
    }
  ]
}
```

Trust policy: not specified by the task.

### Account B

#### 5) `roleC` — one bucket, only for `roleB`

**Task:** a role with full access to a single named S3 bucket, assumable only by
`roleB` from Account A — not by anything else in Account A.

**Explanation:** `roleC` is an **IAM role** in Account B with full access to
**one S3 bucket** (a single storage box) and the files inside it. Only `roleB`
from Account A is allowed to **assume** it. No other user, role, or
administrator in Account A can assume `roleC`.

**Sample trust policy** (only `roleB` from Account A can assume it):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::000000000000:role/roleB" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

**Sample permission policy** (full access to one bucket and its objects):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::my-single-bucket",
        "arn:aws:s3:::my-single-bucket/*"
      ]
    }
  ]
}
```

### The chain

```
roleB (Account A)  ──only job: assume──►  roleC (Account B)  ──access──►  one S3 bucket
```

- `roleB` has no powers except assuming `roleC`.
- `roleC` has no powers except using that one bucket.
- Nothing else in Account A can reach the bucket.

### Role / account summary

| Role | Account | Trusted to be assumed by | Permission policy (what it can do) | Assumes |
|------|---------|--------------------------|------------------------------------|---------|
| `roleA` | A — `000000000000` | Not specified by the task | All services, but `iam:*` denied | Nothing cross-account |
| `roleB` | A — `000000000000` | Not specified by the task | Only `sts:AssumeRole` | `roleC` in Account B |
| `roleC` | B — `111111111111` | Only `roleB` (`arn:aws:iam::000000000000:role/roleB`) | `s3:*` on one bucket + its objects | Nothing |

---

## Q1. Would you give `engine` and `ci` IAM users with access keys in a real production setup, or would you do something different?

**Answer: No — not long-lived IAM user access keys.**

| Principal | Task's approach | What I would use instead | Why |
|-----------|-----------------|--------------------------|-----|
| `ci` (CI/CD) | IAM user + access key | OIDC federation: assume a role with `sts:AssumeRoleWithWebIdentity` | No stored secret; short-lived |
| `engine` on AWS compute | IAM user + access key | IAM role attached to the compute (EC2 instance profile, ECS task role, Lambda execution role, EKS Pod Identity) | No keys; auto-rotated |
| People using CLI/console | IAM users | IAM Identity Center (SSO) + MFA | Short-lived; central offboarding |
| Fallback (if federation/roles are not possible) | IAM user + access key | Least privilege, rotation, Secrets Manager, CloudTrail/Access Analyzer monitoring | Static key risk still exists |

| Problem with IAM user access keys | Consequence |
|-----------------------------------|-------------|
| Never expire | A leaked key works forever |
| Stored in configs/logs/repos | Easy to expose accidentally |
| Hard to rotate | Stale, over-broad permissions pile up |
| Often shared | No per-workload attribution |

### Policy example 1 — `ci` assumes a role via OIDC (no access key)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::000000000000:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:<org>/<repo>:*"
        }
      }
    }
  ]
}
```

### Policy example 2 — `engine` on an EC2 instance assumes a role (no access key)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

---

## Q2. In `roleC`'s trust policy, why does it matter whether you trust the whole Account A root vs. `roleB`'s specific ARN?

**Answer: `root` trusts the whole account; the `roleB` ARN trusts one identity.**

| Trust principal | What it trusts | Who can assume `roleC` | Meets "only `roleB`"? |
|-----------------|----------------|------------------------|------------------------|
| `arn:aws:iam::000000000000:root` | All of Account A | Any Account A principal whose identity policy allows `sts:AssumeRole` on `roleC` | No |
| `arn:aws:iam::000000000000:role/roleB` | Only `roleB` | Only `roleB` | Yes |

| Side | Requirement |
|------|-------------|
| Account A | `roleB`'s identity policy allows `sts:AssumeRole` on `roleC` |
| Account B | `roleC`'s trust policy allows `roleB` |

Note: `root` here does not mean the root user — it is the account principal.

### Policy example 1 — wrong: trusts the whole account (too broad)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::000000000000:root"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### Policy example 2 — correct: trusts only `roleB`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::000000000000:role/roleB"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

When `roleB` assumes `roleC`, the request carries an assumed-role session ARN
(`arn:aws:sts::000000000000:assumed-role/roleB/<session>`), but the trust policy
principal is written as the **role ARN**, as shown above.

---

# Task 4 - Least-Privilege Policy Writing

A custom IAM policy (not a managed policy such as `PowerUserAccess`) for the
`ci` user from Task 3, scoped to only what a CI pipeline needs:

1. Push a Docker image to a specific ECR repository.
2. Deploy a new task definition to a specific ECS service.
3. Read (not write) a specific S3 bucket used for build artifacts.

## Placeholders

| Placeholder | Value used here |
|-------------|-----------------|
| Account A | `000000000000` |
| Region | `us-east-1` |
| ECR repository | `my-app` |
| ECS cluster / service | `prod` / `my-app` |
| Build-artifact bucket | `my-build-artifacts` |
| ECS execution role | `ecsTaskExecutionRole` |

## Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EcrLogin",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "EcrPushToRepo",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage"
      ],
      "Resource": "arn:aws:ecr:us-east-1:000000000000:repository/my-app"
    },
    {
      "Sid": "EcsRegisterTaskDefinition",
      "Effect": "Allow",
      "Action": "ecs:RegisterTaskDefinition",
      "Resource": "*"
    },
    {
      "Sid": "EcsUpdateService",
      "Effect": "Allow",
      "Action": "ecs:UpdateService",
      "Resource": "arn:aws:ecs:us-east-1:000000000000:service/prod/my-app"
    },
    {
      "Sid": "PassEcsExecutionRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::000000000000:role/ecsTaskExecutionRole",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "ecs-tasks.amazonaws.com"
        }
      }
    },
    {
      "Sid": "ReadBuildArtifactsBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::my-build-artifacts"
    },
    {
      "Sid": "ReadBuildArtifactsObjects",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::my-build-artifacts/*"
    }
  ]
}
```

## Why each statement

| Sid | Why it is needed | Why it is scoped this way |
|-----|------------------|---------------------------|
| `EcrLogin` | Gets the Docker login token before `docker push`. | Must be `"*"` - AWS does not support resource-level permissions for `ecr:GetAuthorizationToken`. |
| `EcrPushToRepo` | Exactly the actions `docker push` calls. | Scoped to the one repository ARN. No `ecr:*`, no deletes, no pull-only actions. |
| `EcsRegisterTaskDefinition` | Creates the new task-definition revision. | Must be `"*"` - the new revision does not exist yet, so there is no resource to scope to. |
| `EcsUpdateService` | Points the one service at the new revision. | Scoped to the service ARN. No `CreateService`, `DeleteService`, `RunTask`, etc. |
| `PassEcsExecutionRole` | ECS requires `iam:PassRole` when registering a task definition that references an execution role. | Only the one execution role, plus `iam:PassedToService = ecs-tasks.amazonaws.com` so it cannot be passed elsewhere. |
| `ReadBuildArtifactsBucket` / `ReadBuildArtifactsObjects` | Reads build artifacts. | `ListBucket` on the bucket ARN, `GetObject` on `/*`. No `PutObject`, `DeleteObject`, or `s3:*`. |

## The 4 conditional gaps

### 1) Task role

```json
{
  "Sid": "PassEcsExecutionRole",
  "Effect": "Allow",
  "Action": "iam:PassRole",
  "Resource": [
    "arn:aws:iam::000000000000:role/ecsTaskExecutionRole",
    "arn:aws:iam::000000000000:role/<task-role>"
  ],
  "Condition": {
    "StringEquals": {
      "iam:PassedToService": "ecs-tasks.amazonaws.com"
    }
  }
}
```

### 2) Deployment wait

```json
{
  "Sid": "EcsDescribeService",
  "Effect": "Allow",
  "Action": "ecs:DescribeServices",
  "Resource": "arn:aws:ecs:us-east-1:000000000000:service/prod/my-app"
}
```

### 3) SSE-KMS bucket

```json
{
  "Sid": "KmsDecryptBuildArtifacts",
  "Effect": "Allow",
  "Action": "kms:Decrypt",
  "Resource": "arn:aws:kms:us-east-1:000000000000:key/<key-id>"
}
```

### 4) Read current task definition

```json
{
  "Sid": "EcsDescribeTaskDefinition",
  "Effect": "Allow",
  "Action": "ecs:DescribeTaskDefinition",
  "Resource": "*"
}
```

---

# Task 5 - Find and Fix the Bug

Terraform snippet meant to let `roleB` (Account A) assume `roleC` (Account B).
It is broken in two places: the trust policy and the S3 permissions policy.

## Broken snippet

```hcl
data "aws_iam_policy_document" "roleC_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::000000000000:user/roleB"]
    }
  }
}

resource "aws_iam_role" "roleC" {
  name               = "roleC"
  assume_role_policy = data.aws_iam_policy_document.roleC_trust.json
}

resource "aws_iam_role_policy" "roleC_s3" {
  name = "roleC-s3-access"
  role = aws_iam_role.roleC.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect   = "Allow"
      Action   = "s3:*"
      Resource = "*"
    }]
  })
}
```

## Fixed snippet

```hcl
data "aws_iam_policy_document" "roleC_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"

      # roleB is a role, not a user, and must be the full role ARN.
      # Replace ACCOUNT_A_ID with Account A's actual ID.
      identifiers = [
        "arn:aws:iam::ACCOUNT_A_ID:role/roleB"
      ]
    }
  }
}

resource "aws_iam_role" "roleC" {
  name               = "roleC"
  assume_role_policy = data.aws_iam_policy_document.roleC_trust.json
}

resource "aws_iam_role_policy" "roleC_s3" {
  name = "roleC-s3-access"
  role = aws_iam_role.roleC.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ListBucket"
        Effect = "Allow"
        Action = ["s3:ListBucket"]

        # ListBucket applies to the bucket itself.
        Resource = "arn:aws:s3:::my-bucket"
      },
      {
        Sid    = "ReadWriteObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]

        # GetObject/PutObject apply to objects inside the bucket.
        Resource = "arn:aws:s3:::my-bucket/*"
      }
    ]
  })
}
```

## Why it was failing

- **Trust fix:** `roleB` is a role, not a user — use `role/roleB` so AWS
  matches the right identity.
- **S3 fix:** allow only the 3 needed actions on one bucket instead of `s3:*`
  on everything.
- **Split statements:** `ListBucket` acts on the bucket ARN; `GetObject` /
  `PutObject` act on `bucket/*`, so they need separate statements.
- **Cross-account:** `roleB` also needs permission to assume `roleC`; the trust
  policy alone isn't enough.
