// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using Azure.Mcp.Core.Extensions;
using Azure.Mcp.Core.Models.Option;
using Azure.Mcp.Tools.Aro.Options;
using Azure.Mcp.Tools.Aro.Options.Cluster;
using Azure.Mcp.Tools.Aro.Services;
using Microsoft.Extensions.Logging;
using Microsoft.Mcp.Core.Commands;
using Microsoft.Mcp.Core.Extensions;
using Microsoft.Mcp.Core.Models.Command;

namespace Azure.Mcp.Tools.Aro.Commands.Cluster;

public sealed class ClusterGetCommand(ILogger<ClusterGetCommand> logger, IAroService aroService) : BaseAroCommand<ClusterGetOptions>
{
    private const string CommandTitle = "Get Azure Red Hat OpenShift (ARO) Cluster Details";
    private readonly ILogger<ClusterGetCommand> _logger = logger;
    private readonly IAroService _aroService = aroService;

    public override string Id => "a1b2c3d4-e5f6-7890-abcd-ef1234567890";

    public override string Name => "get";

    public override string Description =>
        "Get Azure Red Hat OpenShift (ARO) cluster details with explicit scope. By default, provide a cluster and resource group, or a resource group for scoped listing. Use --allow-subscription-enumeration only when you intentionally want a full subscription-wide cluster list.";

    public override string Title => CommandTitle;

    public override ToolMetadata Metadata => new()
    {
        Destructive = false,
        Idempotent = true,
        OpenWorld = false,
        ReadOnly = true,
        LocalRequired = false,
        Secret = false
    };

    protected override void RegisterOptions(Command command)
    {
        base.RegisterOptions(command);
        command.Options.Add(OptionDefinitions.Common.ResourceGroup);
        command.Options.Add(AroOptionDefinitions.Cluster);
        command.Options.Add(AroOptionDefinitions.AllowSubscriptionEnumeration);
        command.Validators.Add(commandResults =>
        {
            var clusterName = commandResults.GetValueOrDefault(AroOptionDefinitions.Cluster);
            var resourceGroup = commandResults.GetValueOrDefault(OptionDefinitions.Common.ResourceGroup);
            var allowSubscriptionEnumeration = commandResults.GetValueOrDefault(AroOptionDefinitions.AllowSubscriptionEnumeration);

            if (!string.IsNullOrEmpty(clusterName) && string.IsNullOrEmpty(resourceGroup))
            {
                commandResults.AddError("When specifying a cluster name, the --resource-group option is required.");
            }

            if (string.IsNullOrEmpty(clusterName) && string.IsNullOrEmpty(resourceGroup) && !allowSubscriptionEnumeration)
            {
                commandResults.AddError("To limit data exposure, specify --cluster and --resource-group for a specific cluster, or provide --resource-group for scoped listing. Use --allow-subscription-enumeration to explicitly list all clusters in the subscription.");
            }
        });
    }

    protected override ClusterGetOptions BindOptions(ParseResult parseResult)
    {
        var options = base.BindOptions(parseResult);
        options.ClusterName = parseResult.GetValueOrDefault<string>(AroOptionDefinitions.Cluster.Name);
        options.AllowSubscriptionEnumeration = parseResult.GetValueOrDefault<bool>(AroOptionDefinitions.AllowSubscriptionEnumeration.Name);
        options.ResourceGroup ??= parseResult.GetValueOrDefault<string>(OptionDefinitions.Common.ResourceGroup.Name);
        return options;
    }

    public override async Task<CommandResponse> ExecuteAsync(CommandContext context, ParseResult parseResult, CancellationToken cancellationToken)
    {
        if (!Validate(parseResult.CommandResult, context.Response).IsValid)
        {
            return context.Response;
        }

        var options = BindOptions(parseResult);

        try
        {
            var clusters = await _aroService.GetClusters(
                options.Subscription!,
                options.ClusterName,
                options.ResourceGroup,
                options.Tenant,
                options.RetryPolicy,
                cancellationToken);

            context.Response.Results = ResponseResult.Create(new(clusters ?? []), AroJsonContext.Default.ClusterGetCommandResult);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex,
                "Error getting ARO cluster. Subscription: {Subscription}, ResourceGroup: {ResourceGroup}, ClusterName: {ClusterName}, Options: {@Options}",
                options.Subscription, options.ResourceGroup, options.ClusterName, options);
            HandleException(context, ex);
        }

        return context.Response;
    }

    internal record ClusterGetCommandResult(List<Models.Cluster> Clusters);
}
