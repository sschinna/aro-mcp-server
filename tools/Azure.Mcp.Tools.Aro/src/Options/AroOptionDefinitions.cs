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
    public const string LocationName = "location";
    public const string MasterVmSizeName = "master-vm-size";
    public const string WorkerVmSizeName = "worker-vm-size";
    public const string VersionName = "version";

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

    public static readonly Option<string> Location = new($"--{LocationName}")
    {
        Description = "Azure region to check (e.g. eastus, centralus). If omitted, checks multiple common regions in parallel.",
    };

    public static readonly Option<string> MasterVmSize = new($"--{MasterVmSizeName}")
    {
        Description = "Master node VM size to validate. Default: Standard_D8s_v3.",
    };

    public static readonly Option<string> WorkerVmSize = new($"--{WorkerVmSizeName}")
    {
        Description = "Worker node VM size to validate. Default: Standard_D4s_v3.",
    };

    public static readonly Option<string> Version = new($"--{VersionName}")
    {
        Description = "ARO version to check availability for (e.g. 4.20). If omitted, returns all available versions.",
    };
}
