#!/usr/bin/env bash
# create-user-cost-center.sh
#
# Automates creating a GitHub Enterprise cost center for an individual user,
# adds the user to it, and applies a hard-cap premium request (PRU) budget.
#
# Requirements:
#   - GitHub CLI (gh) authenticated with an enterprise admin token, OR
#   - GITHUB_TOKEN env var set with appropriate permissions
#
# Usage:
#   ./create-user-cost-center.sh \
#     --enterprise <enterprise-slug> \
#     --user <github-username> \
#     --budget-usd <amount>           # e.g. 40.00
#     OR
#     --budget-prus <count>           # e.g. 1000  (converted using --pru-rate)
#     [--pru-rate <usd-per-pru>]      # default: 0.04
#     [--cost-center-name <name>]     # default: <username>
#     [--alert-recipient <username>]  # GitHub username to receive budget alerts
#     [--dry-run]                     # Print API calls without executing
#
# Required permissions on your token:
#   - Enterprise billing: read & write
#
# Examples:
#   # Give user "octocat" a $40 hard-cap PRU budget
#   ./create-user-cost-center.sh --enterprise myenterprise --user octocat --budget-usd 40
#
#   # Give user "octocat" 1000 PRUs (at $0.04/PRU = $40)
#   ./create-user-cost-center.sh --enterprise myenterprise --user octocat --budget-prus 1000
#
#   # Custom PRU rate (e.g. if using premium models at $0.08/PRU)
#   ./create-user-cost-center.sh --enterprise myenterprise --user octocat \
#     --budget-prus 500 --pru-rate 0.08
# ---------------------------------------------------------------------------

set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────────────
ENTERPRISE=""
GH_USER=""
BUDGET_USD=""
BUDGET_PRUS=""
PRU_RATE="0.04"
COST_CENTER_NAME=""
ALERT_RECIPIENT=""
DRY_RUN=false
API_VERSION="2022-11-28"

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}$*${RESET}"; }

# ── Argument parsing ─────────────────────────────────────────────────────────
usage() {
  # Print only the header comment block (up to the divider line)
  sed -n '/^#!/d; /^# -\{10\}/q; s/^# \{0,1\}//p' "$0"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --enterprise)        ENTERPRISE="$2";        shift 2 ;;
    --user)              GH_USER="$2";           shift 2 ;;
    --budget-usd)        BUDGET_USD="$2";        shift 2 ;;
    --budget-prus)       BUDGET_PRUS="$2";       shift 2 ;;
    --pru-rate)          PRU_RATE="$2";          shift 2 ;;
    --cost-center-name)  COST_CENTER_NAME="$2";  shift 2 ;;
    --alert-recipient)   ALERT_RECIPIENT="$2";   shift 2 ;;
    --dry-run)           DRY_RUN=true;           shift   ;;
    -h|--help)           usage                            ;;
    *) error "Unknown option: $1. Run with --help for usage." ;;
  esac
done

# ── Validation ───────────────────────────────────────────────────────────────
[[ -z "$ENTERPRISE" ]] && error "--enterprise is required."
[[ -z "$GH_USER"    ]] && error "--user is required."

if [[ -n "$BUDGET_USD" && -n "$BUDGET_PRUS" ]]; then
  error "Specify either --budget-usd or --budget-prus, not both."
elif [[ -z "$BUDGET_USD" && -z "$BUDGET_PRUS" ]]; then
  error "One of --budget-usd or --budget-prus is required."
fi

# Convert PRUs → USD if needed
if [[ -n "$BUDGET_PRUS" ]]; then
  if ! [[ "$BUDGET_PRUS" =~ ^[0-9]+$ ]]; then
    error "--budget-prus must be a positive integer."
  fi
  BUDGET_USD=$(awk "BEGIN { printf \"%.2f\", $BUDGET_PRUS * $PRU_RATE }")
  info "Converting ${BUDGET_PRUS} PRUs × \$${PRU_RATE}/PRU = \$${BUDGET_USD} USD"
  warn "PRU cost varies by model. \$${PRU_RATE}/PRU is the default base rate."
fi

if ! [[ "$BUDGET_USD" =~ ^[0-9]+(\.[0-9]+)?$ ]] || \
   (( $(awk "BEGIN { print ($BUDGET_USD <= 0) }") )); then
  error "Budget amount must be a positive number."
fi

# Prompt for cost center name if not provided and running interactively
if [[ -z "$COST_CENTER_NAME" ]]; then
  if [[ -t 0 ]] && ! $DRY_RUN; then
    echo -e "${CYAN}Default cost center name:${RESET} ${GH_USER}"
    read -r -p "Enter a custom name (or press Enter to use default): " CUSTOM_NAME
    COST_CENTER_NAME="${CUSTOM_NAME:-$GH_USER}"
  else
    COST_CENTER_NAME="$GH_USER"
  fi
fi

# ── Tool check ───────────────────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  error "GitHub CLI (gh) is not installed. Install from https://cli.github.com"
fi

# ── API helper ───────────────────────────────────────────────────────────────
gh_api() {
  local method="$1"; shift
  local endpoint="$1"; shift

  if $DRY_RUN; then
    echo -e "${YELLOW}[DRY-RUN]${RESET} gh api --method $method $endpoint $*"
    echo "{}"
    return 0
  fi

  gh api \
    --method "$method" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: ${API_VERSION}" \
    "$endpoint" \
    "$@"
}

# ── Main ─────────────────────────────────────────────────────────────────────
echo -e "${BOLD}GitHub Enterprise Cost Center Provisioning${RESET}"
echo "  Enterprise:       $ENTERPRISE"
echo "  User:             $GH_USER"
echo "  Cost center name: $COST_CENTER_NAME"
echo "  Budget (USD):     \$$BUDGET_USD"
[[ -n "$BUDGET_PRUS" ]] && echo "  Budget (PRUs):    $BUDGET_PRUS"
[[ -n "$ALERT_RECIPIENT" ]] && echo "  Alert recipient:  $ALERT_RECIPIENT"
$DRY_RUN && warn "DRY-RUN mode — no API calls will be made."

# ── Step 1: Create cost center ───────────────────────────────────────────────
step "Step 1/3 — Creating cost center \"${COST_CENTER_NAME}\""

RESPONSE=$(gh_api POST \
  "/enterprises/${ENTERPRISE}/settings/billing/cost-centers" \
  -f "name=${COST_CENTER_NAME}")

COST_CENTER_ID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || true)

if [[ -z "$COST_CENTER_ID" ]] && ! $DRY_RUN; then
  error "Failed to create cost center. Response:\n$RESPONSE"
fi

success "Cost center created (id: ${COST_CENTER_ID:-DRY_RUN_ID})"

# ── Step 2: Add user to cost center ─────────────────────────────────────────
step "Step 2/3 — Adding user \"${GH_USER}\" to cost center"

ADD_RESPONSE=$(gh_api POST \
  "/enterprises/${ENTERPRISE}/settings/billing/cost-centers/${COST_CENTER_ID:-DRY_RUN_ID}/resource" \
  --input - <<< "{\"users\":[\"${GH_USER}\"]}")

if echo "$ADD_RESPONSE" | grep -q '"error"' && ! $DRY_RUN; then
  warn "Unexpected response when adding user:\n$ADD_RESPONSE"
else
  success "User \"${GH_USER}\" added to cost center"
fi

# Warn if the user was reassigned from another cost center
if echo "$ADD_RESPONSE" | grep -q '"reassigned_resources"' && \
   ! echo "$ADD_RESPONSE" | grep -q '"reassigned_resources":\[\]'; then
  warn "User was previously assigned to another cost center and has been reassigned."
fi

# ── Step 3: Create budget ────────────────────────────────────────────────────
step "Step 3/3 — Creating hard-cap premium request budget (\$${BUDGET_USD})"

ALERTING_PAYLOAD="{\"will_alert\":false}"
if [[ -n "$ALERT_RECIPIENT" ]]; then
  ALERTING_PAYLOAD="{\"will_alert\":true,\"alert_recipients\":[\"${ALERT_RECIPIENT}\"]}"
fi

BUDGET_RESPONSE=$(gh_api POST \
  "/enterprises/${ENTERPRISE}/settings/billing/budgets" \
  -f  "budget_type=SkuPricing" \
  -f  "budget_product_sku=copilot_premium_request" \
  -f  "budget_scope=cost_center" \
  -f  "budget_entity_name=${COST_CENTER_ID:-DRY_RUN_ID}" \
  -F  "budget_amount=${BUDGET_USD}" \
  -F  "prevent_further_usage=true" \
  -f  "budget_alerting=${ALERTING_PAYLOAD}")

BUDGET_ID=$(echo "$BUDGET_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || true)

if [[ -z "$BUDGET_ID" ]] && ! $DRY_RUN; then
  warn "Budget creation may have failed. Response:\n$BUDGET_RESPONSE"
else
  success "Budget created (id: ${BUDGET_ID:-DRY_RUN_ID})"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Done!${RESET} Summary:"
echo "  Cost center: \"${COST_CENTER_NAME}\" (${COST_CENTER_ID:-DRY_RUN_ID})"
echo "  User:        ${GH_USER}"
echo "  Budget:      \$${BUDGET_USD} USD — hard cap on copilot_premium_request"
[[ -n "$BUDGET_PRUS" ]] && echo "  (~${BUDGET_PRUS} PRUs at \$${PRU_RATE}/PRU)"
[[ -n "$ALERT_RECIPIENT" ]] && echo "  Alerts sent to: ${ALERT_RECIPIENT}"
echo ""
echo "View in GitHub: https://github.com/enterprises/${ENTERPRISE}/settings/billing/cost-centers"
