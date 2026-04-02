// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using Azure.Mcp.Tools.Aro.Commands.Cluster;
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

        services.AddSingleton<ClusterGetCommand>();
    }

    public CommandGroup RegisterCommands(IServiceProvider serviceProvider)
    {
        var aro = new CommandGroup(Name, "Azure Red Hat OpenShift (ARO) cluster setup and issues - Manage, query, and troubleshoot Azure Red Hat OpenShift cluster resources across subscriptions. Use when you need subscription-scoped visibility into ARO cluster metadata—including cluster profiles, networking, API server endpoints, worker node configuration, provisioning state, and cluster issues—for governance, automation, or diagnostics. Requires Azure subscription context.", Title);

        var cluster = new CommandGroup("cluster", "ARO cluster operations - Commands for listing, managing, and diagnosing Azure Red Hat OpenShift clusters in your Azure subscription.");
        aro.AddSubGroup(cluster);

        var clusterGet = serviceProvider.GetRequiredService<ClusterGetCommand>();
        cluster.AddCommand(clusterGet.Name, clusterGet);

        return aro;
    }
}
