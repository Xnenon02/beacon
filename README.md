# Beacon

ASP.NET Core app (`src/Beacon.Api`), deployed to Azure App Service as part of
the clo25 course.

## Run locally

```bash
dotnet run --project src/Beacon.Api
```

Then check the health endpoint on the port `dotnet run` prints:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:<port>/health
```

## Deploy to Azure

See [`TUTORIAL.md`](TUTORIAL.md) for the full walkthrough — prerequisites,
every command run, decisions made, gotchas hit, and teardown.
