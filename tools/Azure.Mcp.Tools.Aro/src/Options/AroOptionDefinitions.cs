// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

namespace Azure.Mcp.Tools.Aro.Options;

public static class AroOptionDefinitions
{
    public const string ClusterName = "cluster";

    public static readonly Option<string> Cluster = new($"--{ClusterName}")
    {
        Description = "Azure Red Hat OpenShift (ARO) cluster name.",
    };
}
