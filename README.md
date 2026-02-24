# Cost Center Individual User Limit

Automate creating a GitHub Enterprise cost center for a specific user, adding them to it, and applying a hard-cap premium request (PRU) budget — all in a single command.

---

## What It Does

When a user needs additional GitHub Copilot Premium Request Units (PRUs), this script:

1. **Creates a cost center** named after the user (or a custom name you provide)
2. **Adds the user** to that cost center so their Copilot usage is tracked there
3. **Sets a hard-cap budget** on `copilot_premium_request` — usage is **blocked** once the limit is reached

---

## Prerequisites

### 1. GitHub CLI (`gh`)

Install from [cli.github.com](https://cli.github.com) and authenticate:

```bash
gh auth login
```

Verify it works:

```bash
gh auth status
```

### 2. Token Permissions

Your token must be for an **Enterprise owner** or **Billing manager** on the enterprise. It needs:

| Permission | Level |
|---|---|
| Enterprise billing | Read & Write |

#### Option A — GitHub CLI (recommended)

When running `gh auth login`, ensure you authorize the token with the `admin:enterprise` scope or use a fine-grained PAT (see Option B).

#### Option B — Personal Access Token (PAT)

1. Go to **GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens**
2. Set **Resource owner** to your enterprise
3. Under **Enterprise permissions**, grant **"Billing and plans" → Read and write**
4. Export the token before running the script:

```bash
export GITHUB_TOKEN=github_pat_xxxxxxxx
```

---

## Usage

```
./create-user-cost-center.sh \
  --enterprise <enterprise-slug> \
  --user <github-username> \
  --budget-usd <amount>           # e.g. 40.00
  OR
  --budget-prus <count>           # e.g. 1000  (converted using --pru-rate)
  [--pru-rate <usd-per-pru>]      # default: 0.04
  [--cost-center-name <name>]     # default: <username>
  [--alert-recipient <username>]  # GitHub username to receive budget alerts
  [--dry-run]                     # Print API calls without executing
```

### Arguments

| Flag | Required | Description |
|---|---|---|
| `--enterprise` | ✅ | The slug of your GitHub Enterprise (e.g. `my-company`) |
| `--user` | ✅ | GitHub username of the user who needs more PRUs |
| `--budget-usd` | ✅ (or `--budget-prus`) | Budget as a USD dollar amount (e.g. `40.00`) |
| `--budget-prus` | ✅ (or `--budget-usd`) | Budget as a number of PRU requests (e.g. `1000`) |
| `--pru-rate` | ❌ | USD cost per PRU for conversion (default: `0.04`) |
| `--cost-center-name` | ❌ | Name for the cost center (default: the username) |
| `--alert-recipient` | ❌ | GitHub username to email at 75%, 90%, 100% budget thresholds |
| `--dry-run` | ❌ | Print what would be done without calling the API |

> **Finding your enterprise slug:** Go to `https://github.com/enterprises` — the slug is the last part of the URL when you click your enterprise (e.g. `https://github.com/enterprises/my-company` → slug is `my-company`).

> **PRU rate note:** The default rate of `$0.04` per PRU applies to base Copilot models. Premium models (e.g. Claude Sonnet, GPT-4o) may cost more per request. Adjust with `--pru-rate` if needed.

---

## Examples

### Give a user a $50 hard-cap budget

```bash
./create-user-cost-center.sh \
  --enterprise my-company \
  --user octocat \
  --budget-usd 50
```

### Give a user 1000 PRUs (converted at default $0.04/PRU = $40)

```bash
./create-user-cost-center.sh \
  --enterprise my-company \
  --user octocat \
  --budget-prus 1000
```

### Give a user 500 PRUs at a custom rate, with alerts

```bash
./create-user-cost-center.sh \
  --enterprise my-company \
  --user octocat \
  --budget-prus 500 \
  --pru-rate 0.08 \
  --alert-recipient billing-admin
```

### Preview what will happen (no API calls made)

```bash
./create-user-cost-center.sh \
  --enterprise my-company \
  --user octocat \
  --budget-prus 1000 \
  --dry-run
```

### Batch — process multiple users from a CSV

Create a file `users.csv` with `username,prus` per line:

```
octocat,1000
monalisa,500
hubot,2000
```

Then loop:

```bash
while IFS=',' read -r user prus; do
  ./create-user-cost-center.sh \
    --enterprise my-company \
    --user "$user" \
    --budget-prus "$prus"
done < users.csv
```

---

## How It Works

The script calls three GitHub REST API endpoints in sequence:

```
POST /enterprises/{enterprise}/settings/billing/cost-centers
  → Creates the cost center

POST /enterprises/{enterprise}/settings/billing/cost-centers/{id}/resource
  → Adds the user to the cost center

POST /enterprises/{enterprise}/settings/billing/budgets
  → Creates a hard-cap SKU-level budget for copilot_premium_request
```

### Sample Output

```
GitHub Enterprise Cost Center Provisioning
  Enterprise:       my-company
  User:             octocat
  Cost center name: octocat
  Budget (USD):     $40.00
  Budget (PRUs):    1000

Step 1/3 — Creating cost center "octocat"
[OK]    Cost center created (id: 3312fdf2-5950-4f64-913d-e734124059c9)

Step 2/3 — Adding user "octocat" to cost center
[OK]    User "octocat" added to cost center

Step 3/3 — Creating hard-cap premium request budget ($40.00)
[OK]    Budget created (id: budget-uuid-here)

Done! Summary:
  Cost center: "octocat" (3312fdf2-5950-4f64-913d-e734124059c9)
  User:        octocat
  Budget:      $40.00 USD — hard cap on copilot_premium_request
  (~1000 PRUs at $0.04/PRU)

View in GitHub: https://github.com/enterprises/my-company/settings/billing/cost-centers
```

---

## Important Notes

- **Hard cap**: The budget is configured with `prevent_further_usage=true`. Once the user hits the limit, Copilot premium requests are **blocked** for that billing cycle.
- **One cost center per user**: A user can only belong to one cost center at a time. If the user is already in another cost center, they will be automatically moved and the script will warn you.
- **Existing enterprise budgets**: If your enterprise has an enterprise-wide `copilot_premium_request` budget with a hard cap, it may block the user before their individual cost center budget is reached. Check **Billing → Budgets and alerts** for conflicts.
- **Budget resets monthly**: GitHub budgets reset each billing cycle. This is not a one-time lifetime limit.
- **Viewing cost centers**: After running, go to `https://github.com/enterprises/<slug>/settings/billing/cost-centers` to confirm.

---

## Troubleshooting

| Error | Likely Cause | Fix |
|---|---|---|
| `gh: command not found` | GitHub CLI not installed | Install from [cli.github.com](https://cli.github.com) |
| `HTTP 401 Unauthorized` | Token missing or expired | Re-authenticate with `gh auth login` |
| `HTTP 403 Forbidden` | Token lacks billing permissions | Ensure token has enterprise billing read/write |
| `HTTP 404 Not Found` | Wrong enterprise slug | Check slug at `github.com/enterprises` |
| `Problems parsing JSON` | Invalid characters in name | Avoid special characters in `--cost-center-name` |
