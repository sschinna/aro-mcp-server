// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

namespace Azure.Mcp.Tools.Aro.Options;

public static class AroOptionDefinitions
{
    public const string ClusterName = "cluster";
    public const string AllowSubscriptionEnumerationName = "allow-subscription-enumeration";
    public const string ProviderName = "provider";
    public const string TopicName = "topic";
    public const string QuestionName = "question";

    public static readonly Option<string> Cluster = new($"--{ClusterName}")
    {
        Description = "Azure Red Hat OpenShift (ARO) cluster name.",
    };

    public static readonly Option<bool> AllowSubscriptionEnumeration = new($"--{AllowSubscriptionEnumerationName}")
    {
        Description = "Explicit opt-in to list all ARO clusters in the provided subscription scope.",
    };

    public static readonly Option<string> Provider = new($"--{ProviderName}")
    {
        Description = "Documentation provider filter. Allowed values: all, azure, redhat. Default: all.",
    };

    public static readonly Option<string> Topic = new($"--{TopicName}")
    {
        Description = "Optional topic keyword filter (for example: networking, ingress, troubleshooting, install, security).",
    };

    public static readonly Option<string> Question = new($"--{QuestionName}")
    {
        Description = "The diagnostic question or issue description to analyze for the ARO cluster.",
    };
}
