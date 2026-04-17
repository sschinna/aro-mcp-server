// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

namespace Azure.Mcp.Tools.Aro.Services;

public interface ILlmService
{
    Task<string> DiagnoseClusterAsync(
        Models.Cluster cluster,
        string question,
        CancellationToken cancellationToken = default);

    Task<string> SummarizeClusterAsync(
        Models.Cluster cluster,
        CancellationToken cancellationToken = default);
}
