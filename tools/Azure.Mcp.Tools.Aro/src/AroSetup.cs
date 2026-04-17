// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using Azure.Mcp.Tools.Aro.Commands.Cluster;
using Azure.Mcp.Tools.Aro.Commands.Documentation;
using Azure.Mcp.Tools.Aro.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Mcp.Core.Areas;
using Microsoft.Mcp.Core.Commands;

namespace Azure.Mcp.Tools.Aro;

public class AroSetup : IAreaSetup
{
    public string Name => "aro";
    public string Title => "ARO Cluster Setup and Issues";

    public void ConfigureServices(IServiceCollection services)
    {
        services.AddSingleton<IAroService, AroService>();
        services.AddSingleton<ILlmService, LlmService>();

        services.AddSingleton<ClusterGetCommand>();
        services.AddSingleton<ClusterDiagnoseCommand>();
        services.AddSingleton<ClusterSummarizeCommand>();
        services.AddSingleton<DocumentationListCommand>();
    }

    public CommandGroup RegisterCommands(IServiceProvider serviceProvider)
    {
        var aro = new CommandGroup(Name, "Azure Red Hat OpenShift (ARO) cluster setup and issues - Manage, query, and troubleshoot Azure Red Hat OpenShift cluster resources across subscriptions. Use when you need subscription-scoped visibility into ARO cluster metadata—including cluster profiles, networking, API server endpoints, worker node configuration, provisioning state, and cluster issues—for governance, automation, or diagnostics. Requires Azure subscription context.", Title);

        var cluster = new CommandGroup("cluster", "ARO cluster operations - Commands for listing, managing, and diagnosing Azure Red Hat OpenShift clusters in your Azure subscription.");
        aro.AddSubGroup(cluster);

        var documentation = new CommandGroup("documentation", "Public documentation operations - Commands for Azure Red Hat OpenShift and Red Hat public guidance references.");
        aro.AddSubGroup(documentation);

        var clusterGet = serviceProvider.GetRequiredService<ClusterGetCommand>();
        cluster.AddCommand(clusterGet.Name, clusterGet);

        var clusterDiagnose = serviceProvider.GetRequiredService<ClusterDiagnoseCommand>();
        cluster.AddCommand(clusterDiagnose.Name, clusterDiagnose);

        var clusterSummarize = serviceProvider.GetRequiredService<ClusterSummarizeCommand>();
        cluster.AddCommand(clusterSummarize.Name, clusterSummarize);

        var documentationList = serviceProvider.GetRequiredService<DocumentationListCommand>();
        documentation.AddCommand(documentationList.Name, documentationList);

        return aro;
    }
}
