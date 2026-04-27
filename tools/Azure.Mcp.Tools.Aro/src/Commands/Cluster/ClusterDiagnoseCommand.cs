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

public sealed class ClusterDiagnoseCommand(
    ILogger<ClusterDiagnoseCommand> logger,
    IAroService aroService,
    ILlmService llmService) : BaseAroCommand<ClusterDiagnoseOptions>
{
    private const string CommandTitle = "Diagnose Azure Red Hat OpenShift (ARO) Cluster Issues with AI";
    private readonly ILogger<ClusterDiagnoseCommand> _logger = logger;
    private readonly IAroService _aroService = aroService;
    private readonly ILlmService _llmService = llmService;

    public override string Id => "b2c3d4e5-f6a7-8901-bcde-f12345678901";
    public override string Name => "diagnose";
    public override string Description =>
        "Diagnose ARO cluster issues using AI analysis. Retrieves cluster data and sends it along with your question to Azure OpenAI for expert diagnosis.";
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
        command.Options.Add(AroOptionDefinitions.Question);
    }

    protected override ClusterDiagnoseOptions BindOptions(ParseResult parseResult)
    {
        var options = base.BindOptions(parseResult);
        options.ClusterName = parseResult.GetValueOrDefault<string>(AroOptionDefinitions.Cluster.Name);
        options.Question = parseResult.GetValueOrDefault<string>(AroOptionDefinitions.Question.Name);
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
                throw new ArgumentException("Cluster name is required for diagnosis.");
            if (string.IsNullOrEmpty(options.ResourceGroup))
                throw new ArgumentException("Resource group is required for diagnosis.");
            if (string.IsNullOrEmpty(options.Question))
                throw new ArgumentException("A diagnostic question is required.");

            var clusters = await _aroService.GetClusters(
                options.Subscription!, options.ClusterName, options.ResourceGroup,
                options.Tenant, options.RetryPolicy, cancellationToken);

            if (clusters.Count == 0)
                throw new InvalidOperationException(
                    $"Cluster '{options.ClusterName}' not found in resource group '{options.ResourceGroup}'.");

            var diagnosis = await _llmService.DiagnoseClusterAsync(
                clusters[0], options.Question, cancellationToken);

            context.Response.Results = ResponseResult.Create(
                new ClusterDiagnoseCommandResult(clusters[0].Name!, options.Question, diagnosis),
                AroJsonContext.Default.ClusterDiagnoseCommandResult);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error diagnosing ARO cluster");
            HandleException(context, ex);
        }

        return context.Response;
    }

    internal record ClusterDiagnoseCommandResult(string ClusterName, string Question, string Diagnosis);
}
