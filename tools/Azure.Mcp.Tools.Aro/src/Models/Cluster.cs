// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

namespace Azure.Mcp.Tools.Aro.Models;

public class Cluster
{
    public string? Id { get; set; }
    public string? Name { get; set; }
    public string? SubscriptionId { get; set; }
    public string? ResourceGroupName { get; set; }
    public string? Location { get; set; }
    public string? ProvisioningState { get; set; }
    public ClusterProfile? ClusterProfile { get; set; }
    public ConsoleProfile? ConsoleProfile { get; set; }
    public ApiServerProfile? ApiServerProfile { get; set; }
    public NetworkProfile? NetworkProfile { get; set; }
    public MasterProfile? MasterProfile { get; set; }
    public IList<WorkerProfile>? WorkerProfiles { get; set; }
    public IList<IngressProfile>? IngressProfiles { get; set; }
    public ServicePrincipalProfile? ServicePrincipalProfile { get; set; }
    public IDictionary<string, string>? Tags { get; set; }
}

public sealed class ClusterProfile
{
    public string? Domain { get; set; }
    public string? Version { get; set; }
    public string? ResourceGroupId { get; set; }
    public string? FipsValidatedModules { get; set; }
}

public sealed class ConsoleProfile
{
    public string? Url { get; set; }
}

public sealed class ApiServerProfile
{
    public string? Visibility { get; set; }
    public string? Url { get; set; }
    public string? Ip { get; set; }
}

public sealed class NetworkProfile
{
    public string? PodCidr { get; set; }
    public string? ServiceCidr { get; set; }
    public string? OutboundType { get; set; }
    public string? PreconfiguredNsg { get; set; }
}

public sealed class MasterProfile
{
    public string? VmSize { get; set; }
    public string? SubnetId { get; set; }
    public string? EncryptionAtHost { get; set; }
    public string? DiskEncryptionSetId { get; set; }
}

public sealed class WorkerProfile
{
    public string? Name { get; set; }
    public string? VmSize { get; set; }
    public int? DiskSizeGB { get; set; }
    public string? SubnetId { get; set; }
    public int? Count { get; set; }
    public string? EncryptionAtHost { get; set; }
}

public sealed class IngressProfile
{
    public string? Name { get; set; }
    public string? Visibility { get; set; }
    public string? Ip { get; set; }
}

public sealed class ServicePrincipalProfile
{
    public string? ClientId { get; set; }
}
