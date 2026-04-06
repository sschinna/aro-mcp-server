// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using System.Text.Json.Serialization;

namespace Azure.Mcp.Tools.Aro.Options.Documentation;

public class DocumentationListOptions : BaseAroOptions
{
    [JsonPropertyName(AroOptionDefinitions.ProviderName)]
    public string? Provider { get; set; }

    [JsonPropertyName(AroOptionDefinitions.TopicName)]
    public string? Topic { get; set; }
}
