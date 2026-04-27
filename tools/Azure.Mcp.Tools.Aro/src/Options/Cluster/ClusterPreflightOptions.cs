// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using System.Text.Json.Serialization;

namespace Azure.Mcp.Tools.Aro.Options.Cluster;

public class ClusterPreflightOptions : BaseAroOptions
{
    [JsonPropertyName(AroOptionDefinitions.LocationName)]
    public string? Location { get; set; }

    [JsonPropertyName(AroOptionDefinitions.MasterVmSizeName)]
    public string? MasterVmSize { get; set; }

    [JsonPropertyName(AroOptionDefinitions.WorkerVmSizeName)]
    public string? WorkerVmSize { get; set; }

    [JsonPropertyName(AroOptionDefinitions.VersionName)]
    public string? Version { get; set; }
}
