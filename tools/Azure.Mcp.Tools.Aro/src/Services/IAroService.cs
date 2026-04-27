// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using Azure.Mcp.Core.Options;
using Azure.Mcp.Tools.Aro.Models;

namespace Azure.Mcp.Tools.Aro.Services;

public interface IAroService
{
    Task<List<Cluster>> GetClusters(
        string subscription,
        string? clusterName,
        string? resourceGroup,
        string? tenant = null,
        RetryPolicyOptions? retryPolicy = null,
        CancellationToken cancellationToken = default);

    Task<List<PreflightResult>> CheckPreflight(
        string subscription,
        string? location,
        string masterVmSize,
        string workerVmSize,
        string? version,
        string? tenant = null,
        RetryPolicyOptions? retryPolicy = null,
        CancellationToken cancellationToken = default);
}
