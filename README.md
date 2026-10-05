# Beacon

A small ASP.NET Core 10 API (search Steam games: price, description, live player counts) deployed to Azure **two ways** from the same code:

| | Web track | Container track |
|---|---|---|
| Runs on | Azure App Service (Linux, B1) | Azure Container Apps, image from Azure Container Registry |
| Infrastructure | `infra/main.bicep` | `infra/container.bicep` |
| Pipeline | `.github/workflows/deploy.yml` | `.github/workflows/deploy-container.yml` |
| Scaling | 3 instances, load balanced by the platform | 1 to 5 replicas, added at 20 concurrent requests each |

Everything is created with Bicep and deployed by GitHub Actions, which sign in to Azure with OIDC (no stored password).

## Start here

**[TUTORIAL.md](TUTORIAL.md)** is the documentation. It explains what was built and why, and how to rebuild all of it step by step from an empty repository and an empty Azure subscription: services, scaling and load balancing, deployment strategy, security design, alternatives considered, known limitations, and troubleshooting.

## Run it locally

```bash
dotnet test --configuration Release
dotnet run --project src/Beacon.Api        # http://localhost:5001
curl http://localhost:5001/health          # OK
```

## Repository layout

| Path | What it is |
|---|---|
| `src/Beacon.Api/` | the app and its `Dockerfile` |
| `tests/Beacon.Tests/` | tests, run by both pipelines before anything is deployed |
| `infra/` | Bicep templates and parameter files (web app, container app, Key Vault) |
| `scripts/` | `provision-all.sh` (build everything from nothing), `deploy-infra.sh`, `deploy-container.sh`, `health-check.sh` |
| `.github/workflows/` | the two pipelines |

The Azure resources are deleted at the end of each working day, so the apps are not running at any given moment. The repository and `TUTORIAL.md` are what matter; `./scripts/provision-all.sh` brings the environment back (see section A10 of the tutorial).
