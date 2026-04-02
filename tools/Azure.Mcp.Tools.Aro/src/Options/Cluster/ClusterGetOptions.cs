// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using System.Text.Json.Serialization;

namespace Azure.Mcp.Tools.Aro.Options.Cluster;

public class ClusterGetOptions : BaseAroOptions
{
    [JsonPropertyName(AroOptionDefinitions.ClusterName)]
    public string? ClusterName { get; set; }
}
