using System.Text.Json.Serialization;
using Microsoft.Extensions.Caching.Memory;

namespace Beacon.Api.Steam;

public record GameSearchResult(
    int AppId,
    string Name,
    string? HeaderImage,
    string? ShortDescription,
    string PriceDisplay,
    int? PlayerCount
);

public class SteamClient(HttpClient httpClient, IMemoryCache cache)
{
    // Search results and app details (price/description/image) barely change within
    // a few minutes/hours, so they're cached longer. Player counts are meant to look
    // live, so they get a short TTL instead. Cache is per-instance (IMemoryCache), which
    // is fine here: stale player counts for up to a minute is a freshness tradeoff, not a
    // correctness bug, unlike e.g. cached vote counts would be.
    private static readonly TimeSpan SearchCacheDuration = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan DetailsCacheDuration = TimeSpan.FromHours(6);
    private static readonly TimeSpan PlayerCountCacheDuration = TimeSpan.FromSeconds(60);

    public async Task<List<GameSearchResult>> SearchGamesAsync(string term, int maxResults = 10, CancellationToken ct = default)
    {
        var items = await FetchSearchItemsAsync(term, ct);
        var selected = items.Take(maxResults);

        var enrichTasks = selected.Select(item => EnrichGameAsync(item, ct));
        var results = await Task.WhenAll(enrichTasks);

        return results.ToList();
    }

    private async Task<List<StoreSearchItem>> FetchSearchItemsAsync(string term, CancellationToken ct)
    {
        var cacheKey = $"search:{term.Trim().ToLowerInvariant()}";
        if (cache.TryGetValue(cacheKey, out List<StoreSearchItem>? cached))
        {
            return cached ?? [];
        }

        try
        {
            var searchUrl = $"https://store.steampowered.com/api/storesearch/?term={Uri.EscapeDataString(term)}&l=english&cc=us";
            var searchResponse = await httpClient.GetFromJsonAsync<StoreSearchResponse>(searchUrl, ct);
            var items = searchResponse?.Items ?? [];

            cache.Set(cacheKey, items, SearchCacheDuration);
            return items;
        }
        catch (Exception) when (ct.IsCancellationRequested == false)
        {
            // Steam's store API occasionally times out or rate-limits; return no matches
            // rather than failing the whole search request.
            return [];
        }
    }

    private async Task<GameSearchResult> EnrichGameAsync(StoreSearchItem item, CancellationToken ct)
    {
        var detailsTask = GetAppDetailsAsync(item.Id, ct);
        var playerCountTask = GetPlayerCountAsync(item.Id, ct);
        await Task.WhenAll(detailsTask, playerCountTask);

        var details = detailsTask.Result;
        var playerCount = playerCountTask.Result;

        var priceDisplay = details?.IsFree == true
            ? "Free to Play"
            : details?.PriceOverview?.FinalFormatted
              ?? item.Price?.FinalFormatted
              ?? "N/A";

        return new GameSearchResult(
            item.Id,
            details?.Name ?? item.Name,
            details?.HeaderImage ?? item.TinyImage,
            details?.ShortDescription,
            priceDisplay,
            playerCount
        );
    }

    private async Task<AppDetailsData?> GetAppDetailsAsync(int appId, CancellationToken ct)
    {
        var cacheKey = $"details:{appId}";
        if (cache.TryGetValue(cacheKey, out AppDetailsData? cached))
        {
            return cached;
        }

        try
        {
            var url = $"https://store.steampowered.com/api/appdetails?appids={appId}&l=english";
            var response = await httpClient.GetFromJsonAsync<Dictionary<string, AppDetailsEntry>>(url, ct);

            if (response is not null && response.TryGetValue(appId.ToString(), out var entry) && entry.Success)
            {
                // Only cache successes — a Steam hiccup shouldn't get remembered for hours.
                cache.Set(cacheKey, entry.Data, DetailsCacheDuration);
                return entry.Data;
            }
        }
        catch (Exception) when (ct.IsCancellationRequested == false)
        {
            // Steam's store API occasionally times out or rate-limits; fall back to search result data.
        }

        return null;
    }

    private async Task<int?> GetPlayerCountAsync(int appId, CancellationToken ct)
    {
        var cacheKey = $"players:{appId}";
        if (cache.TryGetValue(cacheKey, out int? cached))
        {
            return cached;
        }

        try
        {
            var url = $"https://api.steampowered.com/ISteamUserStats/GetNumberOfCurrentPlayers/v1/?appid={appId}&format=json";
            var response = await httpClient.GetFromJsonAsync<PlayerCountResponse>(url, ct);

            if (response?.Response?.Result == 1)
            {
                cache.Set(cacheKey, response.Response.PlayerCount, PlayerCountCacheDuration);
                return response.Response.PlayerCount;
            }
        }
        catch (Exception) when (ct.IsCancellationRequested == false)
        {
            // Same as above — a failed lookup isn't cached, so the next request retries.
        }

        return null;
    }
}

internal class StoreSearchResponse
{
    [JsonPropertyName("items")]
    public List<StoreSearchItem>? Items { get; set; }
}

internal class StoreSearchItem
{
    [JsonPropertyName("id")]
    public int Id { get; set; }

    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("tiny_image")]
    public string? TinyImage { get; set; }

    [JsonPropertyName("price")]
    public StoreSearchPrice? Price { get; set; }
}

internal class StoreSearchPrice
{
    [JsonPropertyName("final_formatted")]
    public string? FinalFormatted { get; set; }
}

internal class AppDetailsEntry
{
    [JsonPropertyName("success")]
    public bool Success { get; set; }

    [JsonPropertyName("data")]
    public AppDetailsData? Data { get; set; }
}

internal class AppDetailsData
{
    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonPropertyName("short_description")]
    public string? ShortDescription { get; set; }

    [JsonPropertyName("header_image")]
    public string? HeaderImage { get; set; }

    [JsonPropertyName("is_free")]
    public bool IsFree { get; set; }

    [JsonPropertyName("price_overview")]
    public PriceOverview? PriceOverview { get; set; }
}

internal class PriceOverview
{
    [JsonPropertyName("final_formatted")]
    public string? FinalFormatted { get; set; }
}

internal class PlayerCountResponse
{
    [JsonPropertyName("response")]
    public PlayerCountData? Response { get; set; }
}

internal class PlayerCountData
{
    [JsonPropertyName("player_count")]
    public int PlayerCount { get; set; }

    [JsonPropertyName("result")]
    public int Result { get; set; }
}
