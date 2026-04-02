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
    public IList<IngressProfile>? IngressProfiles { get; set; }
    public AroServicePrincipalProperties? ServicePrincipalProfile { get; set; }
}

internal sealed class AroServicePrincipalProperties
{
    public string? ClientId { get; set; }
    public string? ClientSecret { get; set; }
}
