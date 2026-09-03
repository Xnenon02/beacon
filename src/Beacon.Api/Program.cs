using Beacon.Api.Steam;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddMemoryCache();
builder.Services.AddHttpClient<SteamClient>(client =>
{
    client.Timeout = TimeSpan.FromSeconds(10);
    client.DefaultRequestHeaders.UserAgent.ParseAdd("BeaconApp/1.0 (clo25 course project)");
});

var app = builder.Build();

app.UseDefaultFiles();
app.UseStaticFiles();

app.MapGet("/api/status", () => new
{
    app = "Beacon",
    status = "running"
});

// Health check. Used by App Service (week 35), by health-check.sh (week 36)
// and by the container (week 38). Do not remove.
app.MapGet("/health", () => Results.Ok("OK"));

app.MapGet("/api/games/search", async (string query, SteamClient steamClient, CancellationToken ct) =>
{
    if (string.IsNullOrWhiteSpace(query))
    {
        return Results.Ok(Array.Empty<GameSearchResult>());
    }

    var results = await steamClient.SearchGamesAsync(query, ct: ct);
    return Results.Ok(results);
});

app.Run();

// Makes Program visible to the test project.
public partial class Program { }