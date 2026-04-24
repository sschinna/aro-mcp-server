// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using System.Text.Json;
using Azure.Core;
using Azure.Mcp.Core.Options;
using Azure.Mcp.Core.Services.Azure;
using Azure.Mcp.Core.Services.Azure.Subscription;
using Azure.Mcp.Core.Services.Azure.Tenant;
using Azure.Mcp.Core.Services.Caching;
using Azure.Mcp.Tools.Aro.Commands;
using Azure.Mcp.Tools.Aro.Models;
using Azure.ResourceManager;
using Azure.ResourceManager.Resources;
using Microsoft.Extensions.Logging;

namespace Azure.Mcp.Tools.Aro.Services;

public sealed class AroService(
    ISubscriptionService subscriptionService,
    ITenantService tenantService,
    ICacheService cacheService,
    ILogger<AroService> logger) : BaseAzureService(tenantService), IAroService
{
    private readonly ISubscriptionService _subscriptionService = subscriptionService ?? throw new ArgumentNullException(nameof(subscriptionService));
    private readonly ICacheService _cacheService = cacheService ?? throw new ArgumentNullException(nameof(cacheService));
    private readonly ILogger<AroService> _logger = logger;

    private const string CacheGroup = "aro";
    private const string AroCacheKey = "clusters";
    private const string AroResourceType = "Microsoft.RedHatOpenShift/openShiftClusters";
    private const string AroApiVersion = "2023-11-22";
    private static readonly TimeSpan s_cacheDuration = CacheDurations.ServiceData;

    public async Task<List<Cluster>> GetClusters(
        string subscription,
        string? clusterName,
        string? resourceGroup,
        string? tenant = null,
        RetryPolicyOptions? retryPolicy = null,
        CancellationToken cancellationToken = default)
    {
        ValidateRequiredParameters((nameof(subscription), subscription));

        var subscriptionResource = await _subscriptionService.GetSubscription(
            subscription, tenant, retryPolicy, cancellationToken);

        if (string.IsNullOrEmpty(clusterName))
        {
            return await ListClusters(subscriptionResource, resourceGroup, subscription, cancellationToken);
        }
        else
        {
            if (string.IsNullOrEmpty(resourceGroup))
            {
                throw new ArgumentException("Resource group is required when specifying a cluster name.");
            }

            return await GetClusterByName(subscriptionResource, resourceGroup, clusterName, subscription, cancellationToken);
        }
    }

    private async Task<List<Cluster>> ListClusters(
        SubscriptionResource subscriptionResource,
        string? resourceGroup,
        string subscription,
        CancellationToken cancellationToken)
    {
        var cacheKey = string.IsNullOrEmpty(resourceGroup)
            ? $"{AroCacheKey}:{subscription}"
            : $"{AroCacheKey}:{subscription}:{resourceGroup}";

        var cachedClusters = await _cacheService.GetAsync<List<Cluster>>(
            CacheGroup, cacheKey, s_cacheDuration, cancellationToken);

        if (cachedClusters != null)
        {
            return cachedClusters;
        }

        var clusters = new List<Cluster>();
        var filter = $"resourceType eq '{AroResourceType}'";

        if (!string.IsNullOrEmpty(resourceGroup))
        {
            filter += $" and resourceGroup eq '{resourceGroup}'";
        }

        await foreach (var resource in subscriptionResource.GetGenericResourcesAsync(
            filter: filter,
            cancellationToken: cancellationToken))
        {
            clusters.Add(ConvertBasicClusterModel(resource.Data));
        }

        await _cacheService.SetAsync(CacheGroup, cacheKey, clusters, s_cacheDuration, cancellationToken);
        return clusters;
    }

    private async Task<List<Cluster>> GetClusterByName(
        SubscriptionResource subscriptionResource,
        string resourceGroup,
        string clusterName,
        string subscription,
        CancellationToken cancellationToken)
    {
        var cacheKey = $"{AroCacheKey}:{subscription}:{resourceGroup}:{clusterName}";

        var cachedCluster = await _cacheService.GetAsync<List<Cluster>>(
            CacheGroup, cacheKey, s_cacheDuration, cancellationToken);

        if (cachedCluster != null)
        {
            return cachedCluster;
        }

        var aroResourceId = new ResourceIdentifier(
            $"/subscriptions/{subscriptionResource.Id.SubscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.RedHatOpenShift/openShiftClusters/{clusterName}");

        var armClient = await CreateArmClientAsync(cancellationToken: cancellationToken);
        var genericResource = armClient.GetGenericResource(aroResourceId);
        var resource = await genericResource.GetAsync(cancellationToken);

        var clusters = new List<Cluster> { ConvertFullClusterModel(resource.Value.Data) };
        await _cacheService.SetAsync(CacheGroup, cacheKey, clusters, s_cacheDuration, cancellationToken);
        return clusters;
    }

    private static readonly string[] s_defaultRegions =
    [
        "eastus", "eastus2", "westus2", "westus3", "centralus",
        "northcentralus", "southcentralus", "westeurope", "northeurope", "uksouth"
    ];

    private const string ComputeSkuApiVersion = "2021-07-01";
    private const string AroVersionApiVersion = "2024-08-12-preview";
    private static readonly HttpClient s_httpClient = new();

    public async Task<List<PreflightResult>> CheckPreflight(
        string subscription,
        string? location,
        string masterVmSize,
        string workerVmSize,
        string? version,
        string? tenant = null,
        RetryPolicyOptions? retryPolicy = null,
        CancellationToken cancellationToken = default)
    {
        ValidateRequiredParameters((nameof(subscription), subscription));

        var accessToken = await GetArmAccessTokenAsync(tenant, cancellationToken);
        var token = accessToken.Token;
        var regions = string.IsNullOrEmpty(location) ? s_defaultRegions : [location];

        var tasks = regions.Select(region =>
            CheckRegionPreflight(token, subscription, region, masterVmSize, workerVmSize, version, cancellationToken));

        var results = await Task.WhenAll(tasks);
        return [.. results.OrderByDescending(r => r.IsEligible).ThenBy(r => r.Location)];
    }

    private async Task<PreflightResult> CheckRegionPreflight(
        string token,
        string subscription,
        string region,
        string masterVmSize,
        string workerVmSize,
        string? version,
        CancellationToken cancellationToken)
    {
        var result = new PreflightResult
        {
            Location = region,
            MasterVmSize = masterVmSize,
            WorkerVmSize = workerVmSize,
        };

        try
        {
            // Check SKUs and versions in parallel
            var skuTask = CheckSkuRestrictions(token, subscription, region, masterVmSize, workerVmSize, cancellationToken);
            var versionTask = GetAroVersions(token, subscription, region, cancellationToken);

            await Task.WhenAll(skuTask, versionTask);

            var (masterRestriction, workerRestriction) = skuTask.Result;
            var versions = versionTask.Result;

            result.MasterVmAvailable = string.IsNullOrEmpty(masterRestriction);
            result.WorkerVmAvailable = string.IsNullOrEmpty(workerRestriction);
            result.MasterVmRestriction = masterRestriction;
            result.WorkerVmRestriction = workerRestriction;
            result.AvailableVersions = versions;

            if (!string.IsNullOrEmpty(version))
            {
                result.MatchedVersion = versions.FirstOrDefault(v => v.StartsWith(version, StringComparison.OrdinalIgnoreCase));
            }

            result.IsEligible = result.MasterVmAvailable && result.WorkerVmAvailable
                && (string.IsNullOrEmpty(version) || result.MatchedVersion != null);

            result.Summary = result.IsEligible
                ? $"Region {region} is eligible: {masterVmSize} and {workerVmSize} available" +
                  (result.MatchedVersion != null ? $", version {result.MatchedVersion} available" : "")
                : $"Region {region} NOT eligible: " +
                  (!result.MasterVmAvailable ? $"{masterVmSize} restricted ({masterRestriction})" : "") +
                  (!result.MasterVmAvailable && !result.WorkerVmAvailable ? ", " : "") +
                  (!result.WorkerVmAvailable ? $"{workerVmSize} restricted ({workerRestriction})" : "") +
                  (!string.IsNullOrEmpty(version) && result.MatchedVersion == null ? $", version {version} not available" : "");
        }
        catch (Exception ex)
        {
            result.Summary = $"Region {region}: error checking — {ex.Message}";
            _logger.LogWarning(ex, "Preflight check failed for region {Region}", region);
        }

        return result;
    }

    private static async Task<(string? masterRestriction, string? workerRestriction)> CheckSkuRestrictions(
        string token,
        string subscription,
        string region,
        string masterVmSize,
        string workerVmSize,
        CancellationToken cancellationToken)
    {
        var url = $"https://management.azure.com/subscriptions/{subscription}/providers/Microsoft.Compute/skus" +
            $"?api-version={ComputeSkuApiVersion}&$filter=location eq '{region}'";

        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

        using var response = await s_httpClient.SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            return ($"API error {(int)response.StatusCode}", $"API error {(int)response.StatusCode}");
        }

        using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        var skus = doc.RootElement.GetProperty("value");

        string? masterRestriction = null;
        string? workerRestriction = null;
        bool masterFound = false;
        bool workerFound = false;

        foreach (var sku in skus.EnumerateArray())
        {
            if (sku.GetProperty("resourceType").GetString() != "virtualMachines")
                continue;

            var skuName = sku.GetProperty("name").GetString();
            if (skuName != masterVmSize && skuName != workerVmSize)
                continue;

            string? restriction = null;
            if (sku.TryGetProperty("restrictions", out var restrictions) && restrictions.GetArrayLength() > 0)
            {
                restriction = restrictions[0].TryGetProperty("reasonCode", out var reason)
                    ? reason.GetString() : "Restricted";
            }

            if (skuName == masterVmSize) { masterFound = true; masterRestriction = restriction; }
            if (skuName == workerVmSize) { workerFound = true; workerRestriction = restriction; }

            if (masterFound && workerFound) break;
        }

        if (!masterFound) masterRestriction = "SKU not found in region";
        if (!workerFound) workerRestriction = "SKU not found in region";

        return (masterRestriction, workerRestriction);
    }

    private static async Task<List<string>> GetAroVersions(
        string token,
        string subscription,
        string region,
        CancellationToken cancellationToken)
    {
        var url = $"https://management.azure.com/subscriptions/{subscription}/providers/Microsoft.RedHatOpenShift/" +
            $"locations/{region}/openshiftversions?api-version={AroVersionApiVersion}";

        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

        using var response = await s_httpClient.SendAsync(request, cancellationToken);

        var versions = new List<string>();
        if (!response.IsSuccessStatusCode)
            return versions;

        using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        if (doc.RootElement.TryGetProperty("value", out var value))
        {
            foreach (var item in value.EnumerateArray())
            {
                if (item.TryGetProperty("properties", out var props) &&
                    props.TryGetProperty("version", out var ver))
                {
                    var v = ver.GetString();
                    if (!string.IsNullOrEmpty(v)) versions.Add(v);
                }
            }
        }

        return versions;
    }

    private static Cluster ConvertBasicClusterModel(GenericResourceData data)
    {
        return new Cluster
        {
            Id = data.Id?.ToString(),
            Name = data.Name,
            SubscriptionId = data.Id?.SubscriptionId,
            ResourceGroupName = data.Id?.ResourceGroupName,
            Location = data.Location.ToString(),
            Tags = data.Tags?.Count > 0 ? new Dictionary<string, string>(data.Tags) : null,
        };
    }

    private static Cluster ConvertFullClusterModel(GenericResourceData data)
    {
        var cluster = ConvertBasicClusterModel(data);

        if (data.Properties != null)
        {
            var properties = JsonSerializer.Deserialize(
                data.Properties,
                AroPropertiesJsonContext.Default.AroClusterProperties);

            if (properties != null)
            {
                cluster.ProvisioningState = properties.ProvisioningState;
                cluster.ClusterProfile = properties.ClusterProfile;
                cluster.ConsoleProfile = properties.ConsoleProfile;
                cluster.ApiServerProfile = properties.ApiserverProfile;
                cluster.NetworkProfile = properties.NetworkProfile;
                cluster.MasterProfile = properties.MasterProfile;
                cluster.WorkerProfiles = properties.WorkerProfiles;
                cluster.WorkerProfilesStatus = properties.WorkerProfilesStatus;
                cluster.IngressProfiles = properties.IngressProfiles;

                if (properties.ServicePrincipalProfile != null)
                {
                    cluster.ServicePrincipalProfile = new ServicePrincipalProfile
                    {
                        ClientId = properties.ServicePrincipalProfile.ClientId,
                    };
                }
            }
        }

        return cluster;
    }
}

/// <summary>
/// Internal model matching the ARM response JSON for ARO cluster properties.
/// </summary>
internal sealed class AroClusterProperties
{
    public string? ProvisioningState { get; set; }
    public ClusterProfile? ClusterProfile { get; set; }
    public ConsoleProfile? ConsoleProfile { get; set; }
    public ApiServerProfile? ApiserverProfile { get; set; }
    public NetworkProfile? NetworkProfile { get; set; }
    public MasterProfile? MasterProfile { get; set; }
    public IList<WorkerProfile>? WorkerProfiles { get; set; }
    public IList<WorkerProfile>? WorkerProfilesStatus { get; set; }
    public IList<IngressProfile>? IngressProfiles { get; set; }
    public AroServicePrincipalProperties? ServicePrincipalProfile { get; set; }
}

internal sealed class AroServicePrincipalProperties
{
    public string? ClientId { get; set; }
    // ClientSecret intentionally excluded — never deserialize or expose secrets in MCP tool output
}
