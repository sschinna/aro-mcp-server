// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

namespace Azure.Mcp.Tools.Aro.Options;

public static class AroOptionDefinitions
{
    public const string ClusterName = "cluster";
    public const string ProviderName = "provider";
    public const string TopicName = "topic";

    public static readonly Option<string> Cluster = new($"--{ClusterName}")
    {
        Description = "Azure Red Hat OpenShift (ARO) cluster name.",
    };

    public static readonly Option<string> Provider = new($"--{ProviderName}")
    {
        Description = "Documentation provider filter. Allowed values: all, azure, redhat. Default: all.",
    };

    public static readonly Option<string> Topic = new($"--{TopicName}")
    {
        Description = "Optional topic keyword filter (for example: networking, ingress, troubleshooting, install, security).",
    };
}
