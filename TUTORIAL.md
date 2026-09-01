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
