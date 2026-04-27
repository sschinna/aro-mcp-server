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

public sealed class ClusterSummarizeCommand(
    ILogger<ClusterSummarizeCommand> logger,
    IAroService aroService,
    ILlmService llmService) : BaseAroCommand<ClusterSummarizeOptions>
{
    private const string CommandTitle = "Summarize Azure Red Hat OpenShift (ARO) Cluster with AI";
    private readonly ILogger<ClusterSummarizeCommand> _logger = logger;
    private readonly IAroService _aroService = aroService;
    private readonly ILlmService _llmService = llmService;

    public override string Id => "c3d4e5f6-a7b8-9012-cdef-123456789012";
    public override string Name => "summarize";
    public override string Description =>
        "Generate an AI-powered summary of an ARO cluster including health assessment, configuration details, and recommendations.";
    public override string Title => CommandTitle;

    public override ToolMetadata Metadata => new()
    {
        Destructive = false,
        Idempotent = true,
        OpenWorld = true,
        ReadOnly = true,
        LocalRequired = false,
        Secret = false
    };

    protected override void RegisterOptions(Command command)
    {
        base.RegisterOptions(command);
        command.Options.Add(OptionDefinitions.Common.ResourceGroup);
        command.Options.Add(AroOptionDefinitions.Cluster);
    }

    protected override ClusterSummarizeOptions BindOptions(ParseResult parseResult)
    {
        var options = base.BindOptions(parseResult);
        options.ClusterName = parseResult.GetValueOrDefault<string>(AroOptionDefinitions.Cluster.Name);
        options.ResourceGroup ??= parseResult.GetValueOrDefault<string>(OptionDefinitions.Common.ResourceGroup.Name);
        return options;
    }

    public override async Task<CommandResponse> ExecuteAsync(
        CommandContext context, ParseResult parseResult, CancellationToken cancellationToken)
    {
        if (!Validate(parseResult.CommandResult, context.Response).IsValid)
            return context.Response;

        var options = BindOptions(parseResult);

        try
        {
            if (string.IsNullOrEmpty(options.ClusterName))
                throw new ArgumentException("Cluster name is required for summarization.");
            if (string.IsNullOrEmpty(options.ResourceGroup))
                throw new ArgumentException("Resource group is required for summarization.");

            var clusters = await _aroService.GetClusters(
                options.Subscription!, options.ClusterName, options.ResourceGroup,
                options.Tenant, options.RetryPolicy, cancellationToken);

            if (clusters.Count == 0)
                throw new InvalidOperationException(
                    $"Cluster '{options.ClusterName}' not found in resource group '{options.ResourceGroup}'.");

            var summary = await _llmService.SummarizeClusterAsync(
                clusters[0], cancellationToken);

            context.Response.Results = ResponseResult.Create(
                new ClusterSummarizeCommandResult(clusters[0].Name!, summary),
                AroJsonContext.Default.ClusterSummarizeCommandResult);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error summarizing ARO cluster");
            HandleException(context, ex);
        }

        return context.Response;
    }

    internal record ClusterSummarizeCommandResult(string ClusterName, string Summary);
}
