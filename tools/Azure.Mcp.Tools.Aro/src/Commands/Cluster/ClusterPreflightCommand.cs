// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using Azure.Mcp.Core.Extensions;
using Azure.Mcp.Tools.Aro.Options;
using Azure.Mcp.Tools.Aro.Options.Cluster;
using Azure.Mcp.Tools.Aro.Services;
using Microsoft.Extensions.Logging;
using Microsoft.Mcp.Core.Commands;
using Microsoft.Mcp.Core.Models.Command;

namespace Azure.Mcp.Tools.Aro.Commands.Cluster;

public sealed class ClusterPreflightCommand(ILogger<ClusterPreflightCommand> logger, IAroService aroService) : BaseAroCommand<ClusterPreflightOptions>
{
    private const string CommandTitle = "ARO Cluster Deployment Pre-flight Check";
    private readonly ILogger<ClusterPreflightCommand> _logger = logger;
    private readonly IAroService _aroService = aroService;

    public override string Id => "b2c3d4e5-f6a7-8901-bcde-f12345678901";

    public override string Name => "preflight";

    public override string Description =>
        "Pre-flight check for ARO cluster deployment. Validates VM SKU availability and ARO version support " +
        "across one or multiple Azure regions in parallel. Use before deploying to avoid SKU restriction failures. " +
        "Returns eligible regions with available VM sizes and matching ARO versions.";

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
        command.Options.Add(AroOptionDefinitions.Location);
        command.Options.Add(AroOptionDefinitions.MasterVmSize);
        command.Options.Add(AroOptionDefinitions.WorkerVmSize);
        command.Options.Add(AroOptionDefinitions.Version);
    }

    protected override ClusterPreflightOptions BindOptions(ParseResult parseResult)
    {
        var options = base.BindOptions(parseResult);
        options.Location = parseResult.GetValueOrDefault<string>(AroOptionDefinitions.Location.Name);
        options.MasterVmSize = parseResult.GetValueOrDefault<string>(AroOptionDefinitions.MasterVmSize.Name);
        options.WorkerVmSize = parseResult.GetValueOrDefault<string>(AroOptionDefinitions.WorkerVmSize.Name);
        options.Version = parseResult.GetValueOrDefault<string>(AroOptionDefinitions.Version.Name);
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
            var results = await _aroService.CheckPreflight(
                options.Subscription!,
                options.Location,
                options.MasterVmSize ?? "Standard_D8s_v3",
                options.WorkerVmSize ?? "Standard_D4s_v3",
                options.Version,
                options.Tenant,
                options.RetryPolicy,
                cancellationToken);

            context.Response.Results = ResponseResult.Create(
                new ClusterPreflightCommandResult(results),
                AroJsonContext.Default.ClusterPreflightCommandResult);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex,
                "Error running preflight check. Subscription: {Subscription}, Location: {Location}, Options: {@Options}",
                options.Subscription, options.Location, options);
            HandleException(context, ex);
        }

        return context.Response;
    }

    internal record ClusterPreflightCommandResult(List<Models.PreflightResult> Regions);
}
