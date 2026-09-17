# Tutorial: Deploying Beacon to Azure App Service

This log captures each command run, in order, along with what happened, any
decisions made, and gotchas hit along the way — written so a classmate can
follow it step by step and get the same result.

## Naming convention

Every resource below follows this pattern:

| Resource            | Placeholder pattern            | Used in this walkthrough |
|----------------------|--------------------------------|---------------------------|
| Resource group        | `rg-clo25-<your-name>-we`     | `rg-clo25-namn-we`        |
| App Service plan      | `asp-clo25-<your-name>-we`    | `asp-clo25-namn-we`       |
| Web app                | `app-clo25-<your-name>-we`   | `app-clo25-namn-we`       |

- **If you're following this tutorial for your own deployment:** replace
  `<your-name>` with your own identifier (e.g. your initials or student ID).
  This matters most for the web app name — it becomes part of a public URL
  (`<name>.azurewebsites.net`) and must be globally unique across all of
  Azure, so `app-clo25-namn-we` will already be taken once someone else uses
  it.
- **The hardcoded names in this doc** (`rg-clo25-namn-we`,
  `asp-clo25-namn-we`, `app-clo25-namn-we`) are real, already-created
  resources from this walkthrough. They're left in the commands as-is so
  they can be copy-pasted directly if you want to manage or reuse *this
  specific* deployment outside the tutorial — just don't expect
  `app-clo25-namn-we` to be free if you try to create your own with that
  exact name.
- The `-we` suffix marks **West Europe**, chosen after the first attempt hit
  a capacity issue in Sweden Central — see Step 1.

## Prerequisites

Before Step 1:

1. **Log in and confirm the active subscription:**

   ```bash
   az login
   az account show --query "{name:name, user:user.name}" -o table
   ```

2. **Confirm the .NET SDK version matches the project target** (.NET 10):

   ```bash
   dotnet --version
   ```

3. **Clone the repo and `cd` into it** so the relative paths used below
   (`src/Beacon.Api`, `artifacts/publish`) resolve correctly.

4. **Run the app locally first**, before touching Azure. This gives you a
   baseline — if something breaks later, you'll know whether the problem is
   in the app or in the deployment:

   ```bash
   dotnet run --project src/Beacon.Api
   ```

   Then, in another terminal, hit the health endpoint on whatever port
   `dotnet run` printed (e.g. `http://localhost:5000/health`):

   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" http://localhost:<port>/health
   ```

   Expect `200` before moving on.

## Step 1: Create the App Service Plan

> **Historical failed attempt — do not copy this command.** It's kept here
> because the failure and the decision it led to are part of the story. It
> uses the plain (non-`-we`) names on purpose, matching what was actually
> typed at the time. The command that actually worked is in Step 3, using
> the `-we`-suffixed names from the table above.

```bash
az appservice plan create \
  --name asp-clo25-namn \
  --resource-group rg-clo25-namn \
  --location swedencentral \
  --sku B1 \
  --is-linux
```

**Result:** Failed.

```
Creating App Service Plan 'asp-clo25-namn' (Linux, SKU: B1).
No available instances to satisfy this request. App Service is attempting to
increase capacity. Please retry your request later or consider enabling Async
Scaling on your app service plan: aka.ms/async-scaling. If urgent, this can be
mitigated by deploying this to a new resource group.
```

**Cause:** Azure had no available Linux B1 capacity in `swedencentral` for
this resource group at the time of the request — a transient regional
capacity issue, not a config error.

**Options when this happens:** retry later, enable Async Scaling, try a
different region, or use a new resource group.

**Decision:** retry in **West Europe** with new resource names, suffixed
`-we`: `rg-clo25-namn-we`, `asp-clo25-namn-we`, `app-clo25-namn-we` (see
Naming convention above — substitute your own `<your-name>`).

## Step 2: Confirm the resource group exists

```bash
az group exists --name rg-clo25-namn-we
```

**Result:** `false` (group didn't exist yet on first run).

If `false`, create it:

```bash
az group create \
  --name rg-clo25-namn-we \
  --location westeurope
```

**Why this step exists:** the App Service plan/webapp commands in Step 3
don't create the resource group for you — if it's missing they fail with
`ResourceGroupNotFound` and do nothing. This is intentional: a typo'd group
name becomes an error instead of silently creating a stray empty group that
sits around costing money. This is also the same check used to confirm a
teardown worked — but there you want the answer to be `false`.

## Step 3: Create the App Service plan and the app

The plan (the machines the app runs on, and what gets scaled in Step 6):

```bash
az appservice plan create \
  --name asp-clo25-namn-we \
  --resource-group rg-clo25-namn-we \
  --location westeurope \
  --sku B1 \
  --is-linux
```

Then the app, linked to the plan via `--plan`:

```bash
az webapp create \
  --name app-clo25-namn-we \
  --resource-group rg-clo25-namn-we \
  --plan asp-clo25-namn-we \
  --runtime "DOTNETCORE:10.0"
```

Both take roughly 30 seconds. Both return a yellow `WARNING` line that is not
an error — the first confirms `(Linux, SKU: B1)`, the second says "Deploy
your code with: az webapp deploy", i.e. exactly the next step.

`--is-linux` is explicit here even though current Azure CLI defaults to
Linux — a command that states what it does is worth five extra characters,
and it protects against an older CLI where the default was Windows (where
`DOTNETCORE:10.0` isn't a valid runtime).

## Step 4: Deploy the code

`az webapp deploy` wants a zip file, not a folder, so the app must be built
and packed first.

Packing is handled by an MSBuild target added once to
`src/Beacon.Api/Beacon.Api.csproj`, just before `</Project>`:

```xml
  <!-- Zips the publish output to app.zip, next to the publish folder -->
  <Target Name="ZipPublishOutput" AfterTargets="Publish">
    <ZipDirectory SourceDirectory="$(PublishDir)"
                  DestinationFile="$(PublishDir)../app.zip"
                  Overwrite="true" />
  </Target>
```

This lives in the project file rather than the terminal because there's no
zip command that works identically everywhere: `zip` exists on Mac/Linux but
not in Git Bash on Windows, and `Compress-Archive` is PowerShell-only.
`dotnet` is available everywhere, and letting the build system produce the
deployable artifact is exactly what the CI/CD pipeline will do from next
week.

Then two commands:

```bash
dotnet publish src/Beacon.Api --configuration Release --output artifacts/publish

az webapp deploy \
  --resource-group rg-clo25-namn-we \
  --name app-clo25-namn-we \
  --src-path artifacts/app.zip \
  --type zip
```

Verify the zip exists (check the file, not the console output — recent
`dotnet` versions print a compact summary and won't show a "Zipping" line
even though the zip is created):

```bash
ls artifacts/
```

Expect both `app.zip` and the `publish/` folder. `artifacts/` is already in
`.gitignore` (from `dotnet new gitignore` in lab 01), so neither the folder
nor the zip can accidentally get committed — confirm with `git status`, it
shouldn't mention them.

Deploy takes 1–2 minutes and ends with `"status": "RuntimeSuccessful"`.
Azure's `SCM_DO_BUILD_DURING_DEPLOYMENT` note in the response can be ignored
here — `dotnet publish` already built the package, which is the whole point
of the step before. That setting matters for source-only deploys.

**Gotcha:** the deploy command's own status polling can fail or report a
misleading status (e.g. `"BuildSuccessful"` with `numberOfInstancesSuccessful:
0`, or a dropped `ConnectionAbortedError`) even when the deployment itself
succeeded. **CLI polling can fail even if deployment succeeds — always verify
the application independently using `/health`** (Step 5), not the JSON status
field alone.

## Step 5: Verify the app responds

Open the app URL in a browser, and check the health endpoint:

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  https://app-clo25-namn-we.azurewebsites.net/health
```

**Result:** `200` — app confirmed live and healthy.

## Step 6: Scale out and verify (K2 evidence)

This is **manual scale-out**, not autoscaling. The **Basic** tier (B1)
supports manually setting the worker count (up to 3), but rule-based
autoscale — where Azure adds/removes instances automatically based on load —
requires the **Standard** tier or higher.

Check the current plan tier/instance count:

```bash
az appservice plan list \
  --resource-group rg-clo25-namn-we \
  --query "[].{Name:name, Tier:sku.name, Instances:sku.capacity}" \
  --output table
```

**Result (before scaling):**

```
Name               Tier    Instances
-----------------  ------  -----------
asp-clo25-namn-we  B1      1
```

Scale the plan from 1 to 3 instances:

```bash
az appservice plan update \
  --name asp-clo25-namn-we \
  --resource-group rg-clo25-namn-we \
  --number-of-workers 3
```

**Result:** succeeded — response confirms `"sku": {"name": "B1", "tier":
"Basic", "capacity": 3}` and `"numberOfWorkers": 3`, `"provisioningState":
"Succeeded"`.

Re-run the same `list` check to verify independently of the update response:

```bash
az appservice plan list \
  --resource-group rg-clo25-namn-we \
  --query "[].{Name:name, Tier:sku.name, Instances:sku.capacity}" \
  --output table
```

**Result (after scaling):**

```
Name               Tier    Instances
-----------------  ------  -----------
asp-clo25-namn-we  B1      3
```

**This is the K2 evidence:** tier `B1`, scaled from 1 → 3 instances, with
load balancing across instances handled automatically by the App Service
plan — confirmed via two independent checks (the update command's own
response, and a separate `list` query), not just a single self-reported
success message.

## Step 7: Configure the health check

**Portal path (for reference):** App Service → **Monitoring** (left menu) →
**Health check** → toggle **Enable**, set path to `/health`, click **Save**.

Worth noting what else lives under **Monitoring**: Alerts, Metrics, Logs,
Diagnostic settings. Health check isn't a random setting buried somewhere —
it belongs among the tools that watch whether the app is healthy, which
says something about its purpose.

**CLI equivalent — set the health check path:**

```bash
az webapp config set \
  --resource-group rg-clo25-namn-we \
  --name app-clo25-namn-we \
  --generic-configurations health_check_path="/health"
```

**Verify it was set:**

```bash
az webapp show \
  --resource-group rg-clo25-namn-we \
  --name app-clo25-namn-we \
  --query siteConfig.healthCheckPath \
  --output tsv
```

**Result (actual):** `C:/Program Files/Git/health` — **not** `/health`.

### Gotcha: Git Bash rewrites the path before Azure ever sees it

If you're running these commands from **Git Bash on Windows** (MINGW), it
automatically rewrites any argument that looks like a POSIX absolute path —
anything starting with a single `/` — into a Windows path before the command
even runs. So `health_check_path="/health"` silently became
`health_check_path="C:/Program Files/Git/health"`. The `az webapp config
set` command itself succeeded; it just set the wrong value. This is a
Windows/Git-Bash-specific trap, not an Azure CLI bug, and it won't happen in
PowerShell, cmd, or a Mac/Linux terminal.

Two ways to work around it — pick whichever fits your setup:

**Option A — double the leading slash (`//health`)**

```bash
az webapp config set \
  --resource-group rg-clo25-namn-we \
  --name app-clo25-namn-we \
  --generic-configurations health_check_path="//health"
```

*How it works:* MSYS's path-conversion heuristic specifically skips
rewriting arguments that start with two slashes, since that pattern is
reserved for UNC network paths (`//server/share`) on Windows. So the literal
string `//health` survives untouched.

*Why it's not quite right:* untouched doesn't mean correct — the value Azure
actually stores is `//health`, two slashes, not `/health`. That's a
different string from the route your app registers
(`app.MapHealthChecks("/health")`), and may not match depending on how
strictly the health-check prober compares paths. Use this only if you've
confirmed it matches; otherwise prefer Option B.

**Option B — disable MSYS path conversion for the command (recommended)**

```bash
MSYS_NO_PATHCONV=1 az webapp config set \
  --resource-group rg-clo25-namn-we \
  --name app-clo25-namn-we \
  --generic-configurations health_check_path="/health"
```

*How it works:* `MSYS_NO_PATHCONV=1` tells Git Bash's MSYS layer to skip its
path-conversion step entirely for this one command, so `/health` is passed
through to `az` exactly as typed.

*Why it's the safer default:* it produces the exact intended value,
`/health`, with no ambiguity. `MSYS_NO_PATHCONV` only means something in Git
Bash/MSYS on Windows; on macOS/Linux terminals it's an unused environment
variable with no effect, and there's no path-mangling bug there to begin
with — same command line works everywhere on those.

**PowerShell/cmd note:** the `VAR=value command` form above is Unix/Git-Bash
syntax and does **not** work in PowerShell or cmd — those shells don't
rewrite `/health` in the first place, so the bug doesn't occur there and no
workaround is needed. If you are in PowerShell, just run:

```powershell
az webapp config set `
  --resource-group rg-clo25-namn-we `
  --name app-clo25-namn-we `
  --generic-configurations health_check_path="/health"
```

Then re-verify with the same `show` command as before, expecting `/health`
this time.

**Result (after Option B fix):** `/health` — confirmed correct.

**Restart the app to apply/observe it in practice:**

```bash
az webapp restart --resource-group rg-clo25-namn-we --name app-clo25-namn-we
```

**Result:** command returned no visible output in the terminal — normal for
`az webapp restart` (it doesn't print a confirmation payload by default).
Success confirmed by re-running the Step 5 health check curl:

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  https://app-clo25-namn-we.azurewebsites.net/health
```

**Result:** `200` — app back up and healthy after restart, with `/health`
now correctly configured as the health check path.

## Step 8: Demolition — tear down everything

Once you're done and have written down what you need (see the intro to this
document — tier, instance count, app name, resource group, and *why*), tear
the whole thing down. Everything in this lab lives inside one resource
group, so deleting the group deletes everything in it.

**First, list what's actually in the resource group**, so you have a record
of what's about to be deleted:

```bash
az resource list \
  --resource-group rg-clo25-namn-we \
  --query "[].{Name:name, Type:type}" \
  --output table
```

**Result:**

```
Name               Type
-----------------  -------------------------
asp-clo25-namn-we  Microsoft.Web/serverFarms
app-clo25-namn-we  Microsoft.Web/sites
```

**Then delete the resource group:**

```bash
az group delete \
  --name rg-clo25-namn-we \
  --yes \
  --no-wait
```

**What the two flags do:**

- `--yes` skips the interactive confirmation prompt (`Are you sure you want
  to perform this operation? (y/n)`) that `az group delete` normally shows
  before deleting anything. Without it, the command would sit there waiting
  for you to type `y`.
- `--no-wait` returns control to your terminal immediately after Azure
  *accepts* the delete request, instead of blocking until every resource in
  the group has actually finished being deleted (which can take a few
  minutes). This is why the terminal shows nothing and returns right away —
  that's expected, not a hang or a silent failure. Deletion keeps running on
  Azure's side in the background.

**Result:** no output — expected, due to `--no-wait`.

**Verify the teardown** by listing the resource group's contents again (or
checking `az group exists`, which should now return `false`):

```bash
az resource list \
  --resource-group rg-clo25-namn-we \
  --query "[].{Name:name, Type:type}" \
  --output table
```

**Result:**

```
(ResourceGroupNotFound) Resource group 'rg-clo25-namn-we' could not be found.
Code: ResourceGroupNotFound
Message: Resource group 'rg-clo25-namn-we' could not be found.
```

This confirms the resource group — and everything inside it (the App
Service plan and the web app) — is gone. If you're ever unsure whether a
`--no-wait` deletion has actually finished, this is the check to re-run; you
can also confirm visually in the Azure portal.

**Because `--no-wait` means the CLI doesn't wait, this verification step can
return `ResourceGroupNotFound` — full success — or, if run too soon, might
still show the group with resources present but disappearing. If that
happens, it's not a failure, just a timing thing: wait a bit and re-run the
check.**

# CI/CD pipeline (lab 03)

## Del 0: rebuilding from scratch

Same five commands as before (group, plan, app, publish, deploy), same
naming convention. This time capacity was a bigger problem than usual:
Sweden Central and West Europe both failed with "no available instances,"
and North Europe failed differently — `Current Limit (B1 VMs): 0`, a real
subscription quota of zero in that region, not a transient issue. West
Europe had already proven to work earlier in the day (this exact
subscription successfully created and scaled a B1 plan there before), so
that's the region worth retrying rather than guessing at untested ones. A
short retry loop (a few attempts, minutes apart) got past the transient
capacity error on the second try. Lesson for next time: if a region fails,
check whether it's the "no available instances" message (transient, worth
retrying) or a quota number in the error (not transient, needs a different
region or a quota increase request).

## Del 1: connecting the repo to Azure

Followed the lab's 8 steps in order — read the real name/address from
Azure rather than trusting memory, enabled basic publishing credentials on
the `scm` site, fetched the publish profile, set it as the
`AZURE_WEBAPP_PUBLISH_PROFILE` GitHub secret, deleted the local copy
immediately and gitignored it, set `SCM_DO_BUILD_DURING_DEPLOYMENT=false`
explicitly, and wrote `.github/workflows/deploy.yml`.

Two things worth a note:

- The lab's own placeholder check (`grep -n "clo25-namn"`) gives a false
  positive here, because this project's naming convention appends a region
  suffix (`-we`), and `app-clo25-namn-we` still contains the substring
  `clo25-namn`. That's expected — the values are correctly filled in, just
  not literally absent from the grep.
- `workflow_dispatch` only works for a workflow file that already exists on
  the repo's *default* branch. Pushed on a feature branch first (per this
  project's own rule of never pushing straight to `main`), which meant the
  pipeline couldn't be dry-run before merging — GitHub simply doesn't
  register a workflow file living only on a branch. Adding a `pull_request`
  trigger as a workaround isn't a good idea for this workflow either, since
  the `deploy` job pushes to the real Azure app — you don't want that
  firing on every PR. So the actual first run only happened at merge time,
  which lines up with what the lab calls the checkpoint anyway.

## Del 2: getting deploy green, and confirming it's not just theater

First run went green immediately — no auth troubleshooting needed this
time (`gh auth setup-git`, done back in lab 02's prep, meant the publish
profile secret was correct on the first try).

Pushed a small, visible text change (added "— deployed via CI/CD" to the
UI's subtitle) specifically to prove the pipeline deploys *real* changes,
not just that the YAML runs. Confirmed two ways: the workflow's own log
went green, and — separately — `curl`ing the live app afterward showed the
new text. The lab's warning about the propagation gap (green != new code
live yet) held up here too: checked immediately after green and it can
still be stale for roughly a minute while App Service swaps to the new
package.

## Del 3: smoke test script (F3)

`scripts/health-check.sh` — a smoke test, not a correctness test. It asks
exactly one question: does the app respond `200` on a given URL? It doesn't
check that the response is *right*, only that something is listening and
healthy. Real correctness checks already ran in the `build` job's
`dotnet test` step.

Built with two arguments: the URL (required — the script refuses to run
without it, with a clear error) and an optional attempt count (defaults to
10, 5 seconds apart). Tested locally both ways before touching the
pipeline: against the real `/health` (succeeded on attempt 1, exit 0), and
against a nonexistent path with only 2 attempts (two `404`s, "Giving up.",
exit 1, done in ~5 seconds instead of the default ~45).

Wired into the `deploy` job *after* the actual deploy step, with
`actions/checkout` added first in that job (the script lives in the repo,
and each job starts on a clean machine with nothing checked out — and
checkout has to come before `download-artifact`, since checkout clears the
working directory and would delete the downloaded package if it ran
second).

**The honest limitation, worth remembering:** a green smoke test here only
proves the app answered `200` — not that it's running the *new* code. If
the health check runs moments after deploy finishes, it's entirely possible
the still-running old version answers first, before App Service has
swapped to the new package. What this script *does* reliably catch is the
worst case — a new version that fails to start at all, which would make
`/health` stop responding and turn the *next* deploy's health check red.
The loop (attempts + delay) exists specifically so a normal, brief restart
window doesn't get mistaken for that failure — a single `curl` with no
retry would have flagged this exact deploy as broken on the first run of
the day, purely because `/health` hadn't started answering yet (a handful
of `404`s while the new app boots is normal on a fresh app; ten in a row is
a real failure).

**Idea for later (F2):** the only way to make this script actually confirm
"the new code is live," not just "something answered `200`," is for
`/health` to report a version or build identifier the script can compare
against what was just deployed. Worth doing once the app has a natural
place to put that (a build-time stamp, a commit SHA, something similar).

## Fördjupning 06 notes

Read the live log stream (`az webapp log tail`) through a restart — got the
full startup sequence (`Running the command: dotnet "Beacon.Api.dll"` →
`Now listening on...` → `Application started.` → `Hosting environment:
Production` → `Site startup probe succeeded after 70.7 seconds`), and hit
the documented "stream interrupts itself" behavior firsthand: it cut off
with `Log stream interrupted. Exiting live log stream.` right before the
final `Site started.` line, because the restart tears down the very
connection you're watching from. Confirmed the app was actually up anyway
via a plain `curl` — `200`.

`httpsOnly` was `False` by default (as it is on every app `az webapp
create` makes) — that doesn't mean the app lacks HTTPS, every
`*.azurewebsites.net` app has a certificate automatically. It only
controls whether `http://` gets redirected to `https://`. Turned it on
(`az webapp update --https-only true`) and confirmed with `curl`: `http://`
now returns a `301` to the `https://` URL instead of answering directly.

**On `paths-ignore` vs. `paths`:** decided to stick with a deny-list
(`paths-ignore: ['**.md', '**.http']`) rather than switching to an
allow-list like `paths: ['src/**']`. Checked it against this project's own
history: under an allow-list, 2 of the 3 CI/CD-related pushes made today —
including the one that added the pipeline itself — would have silently
never triggered a run, since they only touched `.github/workflows/` and
`scripts/`. A deny-list's worst case is a wasted ~78s run; an allow-list's
worst case is a push that should deploy and doesn't, with nothing visibly
wrong. Added `'**.http'` (matching `requests.http`, a dev-only file that
never affects build or runtime behavior) using the glob rather than the
literal filename, so it still applies if such a file ever moves into a
subfolder.

## Infrastructure as Code (Bicep) — lab 04, 2026-09-10

Chose **Plan A** on Tuesday (Fördjupning 07): `az ad sp create-for-rbac`
succeeded once run with `MSYS_NO_PATHCONV=1` — the failure earlier that day
was the same Git Bash path-mangling bug as the `health_check_path` gotcha
above, not a real permissions problem (see the correction note this
produced, merged from `docs/plan-a-correction`).

### What the template creates, and why (K1)

`infra/main.bicep` describes two resources: the App Service plan
(`Microsoft.Web/serverfarms`) and the web app (`Microsoft.Web/sites`), linked
via `serverFarmId: plan.id` inside the template rather than a hardcoded
resource ID. Nothing else — no resource group (it's deployed *into* one that
already exists; `az group create` lives in the deploy script instead, not
the template) and no app settings (declaring `appSettings` would replace
*all* existing ones, wiping `SCM_DO_BUILD_DURING_DEPLOYMENT` from lab 03 —
deliberately left out of the template rather than fixed with a merge, since
getting that merge wrong silently loses settings).

### Scaling (K2)

`sku.capacity: instanceCount`, parameterized with a default of `2` but
deployed with `instanceCount = 3` in `infra/main.bicepparam` — matching the
manual scale-out already done by hand in week 35 (`az appservice plan update
--number-of-workers 3`). The value isn't the template's default; it's a
choice, now written down instead of living only in shell history.

### Security in the template (K2)

`httpsOnly: true` and `minTlsVersion: '1.3'` on the site config, plus
`healthCheckPath: '/health'`. `minTlsVersion` isn't decorative — it raises
the floor a client must meet during the TLS handshake; every modern browser
and `curl` already clears 1.3, so nothing observable changes, but a
TLS-1.2-only client would now be refused. `what-if` (Step 6) confirmed both
`httpsOnly` and `alwaysOn` were actually `false` on the live app before this
deploy — settings assumed correct from week 35 but never verified until they
were written down as code and compared against reality.

### How it's deployed, and why (F2, Komp1)

`scripts/deploy-infra.sh` wraps `az deployment group create` (plus a resource
group existence guard, since the group is torn down daily) and supports
`--what-if` for a dry run. It's wired into `.github/workflows/deploy.yml` as
its own `infra` job, running in parallel with `build`, with `deploy` gated on
`needs: [build, infra]` so the app can never deploy before the plan exists.
Chosen over inlining the Azure CLI calls directly in the YAML so the exact
same script can be run by hand (`./scripts/deploy-infra.sh rg-clo25-namn-we`)
or by the pipeline — one implementation, two callers.

**Two real failures hit during Del 3–4, not simulated ones:**

1. `azure/login@v3` was first configured with separate `client-id` /
   `client-secret` / `tenant-id` / `subscription-id` inputs, matching the
   four secrets that happened to already exist in the repo. The action
   rejected `client-secret` outright — v3 only accepts a combined `creds`
   JSON secret, or OIDC (no secret at all, `client-id`/`tenant-id`/
   `subscription-id` plus `id-token: write`). Fixed by re-running
   `create-for-rbac` against the existing identity (patched in place, not
   duplicated) and storing the result as `AZURE_CREDENTIALS`.
2. The `deploy` job then failed with `401 Unauthorized` from
   `azure/webapps-deploy@v3` — the app had been rebuilt earlier the same day
   and basic publishing credentials were off again, exactly the gotcha noted
   in Step 4 above. Fixed the same way: `az resource update` on
   `basicPublishingCredentialsPolicies`, then a fresh publish profile.

### Identity vs. role vs. scope — the tradeoff (K2, Komp2)

The service principal's role assignment is scoped to the resource group
(`--scopes .../resourceGroups/rg-clo25-namn-we`), not the subscription. That
means the assignment — unlike the identity itself — does **not** survive a
teardown, and the pipeline would fail on `AuthorizationFailed` next time
until it's re-granted. The alternative (scope the role at the subscription
level) would survive teardown and remove this problem entirely, at the cost
of letting the pipeline create or delete anything in the whole subscription,
not just this one resource group. Chose the narrow scope and paid for it
with a script, not a wider blast radius.

**Del 4 removed the two things that used to require doing by hand every
lesson day:**

- **Publish-profile rotation** — `deploy` now authenticates with the same
  service principal as `infra` (`azure/login` step added, `publish-profile`
  input removed from `azure/webapps-deploy`). The key that used to die with
  every rebuilt app is gone entirely; the identity in Entra ID doesn't need
  rotating.
- **The role assignment itself** — `scripts/deploy-infra.sh` now looks up
  the identity by name (`SP_NAME`, not a hardcoded object ID — the script
  queries Entra ID for it, so no tenant identifiers live in the repo) and
  re-grants `Contributor` on the resource group if the assignment is
  missing. Guarded with `2>/dev/null || true` so a lookup failure (e.g. the
  pipeline's own identity not being allowed to read the directory) skips the
  block silently rather than failing the whole deployment — in practice,
  this run's pipeline *could* read the directory and printed `pipeline
  identity already has Contributor`, so the guard wasn't needed this time,
  but stays as protection for whenever it is.

Net effect: rebuilding from scratch next lesson day is one command
(`./scripts/deploy-infra.sh rg-clo25-namn-we`), with no manual key or role
step left to forget.

## Containerizing the app: ACR + Container Apps — lab 05, 2026-09-17

### Docker Desktop doesn't work on this machine, and why that's fine

`docker build` failed with `docker: command not found`; installing Docker
Desktop failed at first launch with "Virtualization support not detected" —
"Contact your IT admin," meaning virtualization is locked at a policy level
on this school-managed machine, not just off in BIOS. Confirmed once and
stopped there rather than fighting a setting that isn't mine to change.

Correcting an assumption from earlier in the week: Docker's WSL2 backend
does *not* require the full "Hyper-V" Windows feature — only the lighter
"Virtual Machine Platform" component plus CPU-level virtualization
(VT-x/AMD-V). It "just worked" in the past because that hardware setting was
already on by default, not because nothing was needed. Here it's actively
blocked, so the point is moot either way.

**Consequence: every image in this course is built with `az acr build`
instead of `docker build`.** Same `--file`, same trailing `.` build context,
same result — the difference is only *where* the build runs (a build
container in Azure, not a local Docker daemon), which is exactly why no
local Docker is needed at all. `docker run -p 8080:8080` for a quick local
smoke test has no real equivalent for the same reason — ACR is a registry,
not a runtime, and `az acr run` is built for build-time steps, not for
starting a long-lived container to curl against. Azure Container Instances
(ACI) would be the closest match, but the course's own answer is simpler:
skip the local step, deploy straight to Container Apps, and test the live
URL instead.

### What got built, and why (K1)

`infra/container.bicep` grew in two passes, mirroring the hard ordering
constraint (registry → image → environment/app — a Container App deploy
fails outright if the image it points to doesn't exist yet):

1. **Registry only** (`Microsoft.ContainerRegistry/registries`,
   `acrclo25namnwe`) — deployed alone first. It already existed (created
   manually before the template existed), so this `what-if` showed only
   `~ Modify` (`adminUserEnabled: false → true`), no `+`.
2. **Environment + Container App added** (`Microsoft.App/managedEnvironments`
   `cae-clo25-namnwe`, `Microsoft.App/containerApps` `ca-clo25-namnwe`) once
   `beacon:v1` was actually pushed. `what-if` showed exactly 2 `+` and
   nothing else — the registry, unchanged, stayed `~`.

`adminUserEnabled: true` on the registry is a deliberate, written-down
trade-off: it's the simplest way for the Container App to pull the image
(username + password), not the best one. The better way — managed identity
+ an `AcrPull` role assignment, no stored password at all — is the same
upgrade path as OIDC for the pipeline, both slated for week 40.

### Scaling and security as code (K2)

`scale.minReplicas: 1`, `maxReplicas: 5`, `concurrentRequests: 20` —
defaults kept as-is (the exercise meant to set these deliberately was
missed), so the honest note here is *why* they're defaults rather than a
chosen number: they're reasonable for a course project with no real traffic,
and the thing to change first under real load would be `concurrentRequests`
(lower it to scale out sooner) before touching the replica ceiling.

Compare to App Service's scaling story: `sku.capacity: 3` there was a fixed
worker count. Here it's a *range* plus a *rule* — Container Apps decides how
many replicas to run, live, based on concurrent HTTP load. Same idea as
`az appservice plan update --number-of-workers 3` from week 35, one level
more automatic.

`acr.listCredentials()` inside the template means the registry password is
never typed anywhere, never lands in shell history, never touches Git — the
template only describes *how* to fetch it at deploy time. `cpu:
json(containerCpu)` exists because Bicep has no native decimal literal;
skipping `json()` produces a compile error that doesn't explain itself.

### Deploying it, and a real bug hit twice (F2, Komp1)

`scripts/deploy-container.sh` is a copy of `deploy-infra.sh` differing in
exactly three lines (`PARAM_FILE`, `TEMPLATE`, the `DEPLOYMENT_NAME` prefix)
— verified with `diff -u`, not by eye. It inherited the role-assignment
self-healing block from week 37 unchanged, which is why it isn't part of the
diff at all.

**The Git Bash path-mangling bug (first hit in week 37 on
`health_check_path`) struck a third time**, this time on the self-healing
block's `--scope "/subscriptions/..."` argument: without
`MSYS_NO_PATHCONV=1` exported, the deployment itself succeeded but the
role-check step failed with `MissingSubscription` — the leading slash got
rewritten into a Windows path again. Same root cause, third different
symptom (`health_check_path` → `az ad sp create-for-rbac --scopes` →
this). Worth writing down as a pattern, not three separate bugs: *any*
`az` argument starting with a single `/`, run from Git Bash on Windows, is
suspect until proven otherwise.

**A second, unrelated failure**: pushing today's changes triggered *both*
pipelines (container track's `scripts/` change isn't excluded by either
workflow's `paths-ignore`), and the App Service pipeline's health check
failed with ten straight `404`s. Direct `curl` moments later returned `200`
— the `infra` job's Bicep deploy had reset `alwaysOn`/health-check
configuration, restarting the app, and the pipeline's ~45-second retry
budget ran out just before the app finished restarting. Re-running the
failed job confirmed it: a false negative from timing, not a real
regression — the same class of gotcha as the `000`/`503` responses
documented in Step 4 above, just manifesting as `404` this time.

### Rollout behavior observed (K4)

Pushed a trivial visible change (`/api/status` response text) through the
Plan A pipeline and inspected `az containerapp revision list --all`
afterward:

```
Rev                       Active    Traffic
------------------------  --------  -------
ca-clo25-namnwe--x6bubwc  False     0
ca-clo25-namnwe--0000001  True      0
ca-clo25-namnwe--0000002  True      100
```

The old revisions were **not deleted** — they still exist, just deactivated
or at 0% traffic, while the newest one holds 100%. This is Container Apps'
built-in rolling-style behavior: nothing was configured for it, it's the
default. Compared to week 36's rolling/blue-green/canary distinctions: this
reads as rolling (one new revision fully replaces traffic, old ones kept
around rather than both serving simultaneously as blue-green would, and
without the gradual traffic-split a canary would use) — though Container
Apps *can* do traffic-splitting across revisions manually if asked to
(Fördjupning 10 territory).

**The honest limit of the health check here, same shape as week 36's
lesson**: a green `Health check after deployment` step proves the app
answers `200` — not that it's the *new* revision answering. If a bad
revision failed to start, Container Apps would simply keep serving the old
one at 100% traffic, and the health check would still pass. The only way to
see that is `revision list`, not the pipeline's own output.

### Two pipelines, one test, run twice (Komp1 reflection)

`dotnet test` now runs in both `deploy.yml` and `deploy-container.yml`,
independently. Real duplication, but the safer default: if it lived in only
one, whichever pipeline skipped it would be the one capable of shipping code
whose tests fail — a test that gates one deploy path and not the other is
worse than no test, since it teaches that tests are a step in a file rather
than a gate before any release. The actual fix for the duplication — a
shared `build`/`test` job, or a reusable workflow both call — is known and
not built here; recognizing the option is the point, not implementing it
today.

### Tearing down four resources instead of one

`deploy-infra.sh` only ever knew about the App Service track. Today added a
registry, a Container Apps environment, and a container app — four resources
across two scripts, in a strict order (registry before image before app).
`scripts/provision-all.sh` exists purely to encode that order as a file
instead of a memory: it calls `deploy-infra.sh`, creates the registry
directly (since `container.bicep` can't yet — the app inside it needs an
image that doesn't exist yet), builds the image, then calls
`deploy-container.sh`. No new logic, just the missing two commands plus the
two scripts already written, chained. Checked with `bash -n` before ever
being run for real, since it's the one script in this course committed and
then torn down out from under before it was ever exercised.

Teardown used `properties.provisioningState` instead of `az group exists`
this time — a Container Apps environment can take upward of ten minutes to
empty, and `exists` would just report `true` the whole time with no signal
that anything is actually progressing. `provisioningState` answers
`Deleting` mid-flight instead of leaving that ambiguous.

Net effect for next lesson day: `./scripts/provision-all.sh rg-clo25-namn-we
acrclo25namnwe` first thing, before anything else — the Container Apps
environment is the slowest thing to create in the whole course, so starting
it early and reading/writing while it provisions is the way to spend that
wait, not watching it.
