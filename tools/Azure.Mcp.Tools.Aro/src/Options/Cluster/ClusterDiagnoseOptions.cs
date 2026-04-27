// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using System.Text.Json.Serialization;

namespace Azure.Mcp.Tools.Aro.Options.Cluster;

public class ClusterDiagnoseOptions : BaseAroOptions
{
    [JsonPropertyName(AroOptionDefinitions.ClusterName)]
    public string? ClusterName { get; set; }

    [JsonPropertyName(AroOptionDefinitions.QuestionName)]
    public string? Question { get; set; }
}
