// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using Azure.Mcp.Core.Models.Option;
using Azure.Mcp.Tools.Aro.Options;
using Azure.Mcp.Tools.Aro.Options.Documentation;
using Microsoft.Extensions.Logging;
using Microsoft.Mcp.Core.Commands;
using Microsoft.Mcp.Core.Extensions;
using Microsoft.Mcp.Core.Models.Command;

namespace Azure.Mcp.Tools.Aro.Commands.Documentation;

public sealed class DocumentationListCommand(ILogger<DocumentationListCommand> logger) : BaseAroCommand<DocumentationListOptions>
{
    private const string CommandTitle = "List Azure and Red Hat Public ARO Documentation";
    private readonly ILogger<DocumentationListCommand> _logger = logger;

    private static readonly List<Models.PublicDocument> Catalog =
    [
        new()
        {
            Title = "Azure Red Hat OpenShift overview",
            Provider = "azure",
            Category = "overview",
            Url = "https://learn.microsoft.com/azure/openshift/intro-openshift",
            Description = "Service overview, architecture, and core capabilities for ARO."
        },
        new()
        {
            Title = "Tutorial: Create an Azure Red Hat OpenShift 4 cluster",
            Provider = "azure",
            Category = "deployment",
            Url = "https://learn.microsoft.com/azure/openshift/tutorial-create-cluster",
            Description = "Step-by-step guide to deploy an ARO cluster."
        },
        new()
        {
            Title = "Configure prerequisites for ARO",
            Provider = "azure",
            Category = "deployment",
            Url = "https://learn.microsoft.com/azure/openshift/howto-setup-environment",
            Description = "Subscription preparation, permissions, providers, and network prerequisites."
        },
        new()
        {
            Title = "Connect to an ARO cluster",
            Provider = "azure",
            Category = "access",
            Url = "https://learn.microsoft.com/azure/openshift/tutorial-connect-cluster",
            Description = "Get kubeadmin credentials and connect with oc/kubectl."
        },
        new()
        {
            Title = "Private cluster in ARO",
            Provider = "azure",
            Category = "networking",
            Url = "https://learn.microsoft.com/azure/openshift/howto-create-private-cluster-4x",
            Description = "Deploy ARO with private API and ingress endpoints."
        },
        new()
        {
            Title = "Configure ingress for ARO",
            Provider = "azure",
            Category = "networking",
            Url = "https://learn.microsoft.com/azure/openshift/howto-custom-domain",
            Description = "Custom domains, certificates, and ingress endpoint configuration."
        },
        new()
        {
            Title = "ARO troubleshooting",
            Provider = "azure",
            Category = "troubleshooting",
            Url = "https://learn.microsoft.com/troubleshoot/azure/azure-red-hat-openshift/welcome-azure-redhat-openshift",
            Description = "Official Azure troubleshooting hub for ARO platform issues."
        },
        new()
        {
            Title = "ARO FAQ",
            Provider = "azure",
            Category = "reference",
            Url = "https://learn.microsoft.com/azure/openshift/openshift-faq",
            Description = "Common questions and guidance for ARO operations."
        },
        new()
        {
            Title = "OpenShift Container Platform Documentation",
            Provider = "redhat",
            Category = "overview",
            Url = "https://docs.redhat.com/en/documentation/openshift_container_platform",
            Description = "Primary Red Hat OpenShift documentation portal."
        },
        new()
        {
            Title = "Installing OpenShift Container Platform",
            Provider = "redhat",
            Category = "deployment",
            Url = "https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/installing/index",
            Description = "Installation concepts and platform deployment guidance."
        },
        new()
        {
            Title = "OpenShift networking",
            Provider = "redhat",
            Category = "networking",
            Url = "https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/networking/index",
            Description = "Networking, ingress, routes, and network policy deep dive."
        },
        new()
        {
            Title = "OpenShift authentication and authorization",
            Provider = "redhat",
            Category = "security",
            Url = "https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/authentication_and_authorization/index",
            Description = "Identity providers, RBAC, OAuth, and authN/authZ operations."
        },
        new()
        {
            Title = "OpenShift monitoring",
            Provider = "redhat",
            Category = "observability",
            Url = "https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/monitoring/index",
            Description = "Metrics, alerting, and cluster observability configuration."
        },
        new()
        {
            Title = "OpenShift etcd",
            Provider = "redhat",
            Category = "control-plane",
            Url = "https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/etcd/index",
            Description = "etcd operations, backups, restore, and troubleshooting."
        },
        new()
        {
            Title = "OpenShift updating clusters",
            Provider = "redhat",
            Category = "lifecycle",
            Url = "https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/updating_clusters/index",
            Description = "Upgrade channels, update workflows, and version management."
        },
        new()
        {
            Title = "OpenShift support and troubleshooting",
            Provider = "redhat",
            Category = "troubleshooting",
            Url = "https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/support/index",
            Description = "Troubleshooting procedures and support data collection."
        }
    ];

    public override string Id => "b8b06c4b-e9ef-4d59-a4b6-4f01df3d4b0f";

    public override string Name => "list";

    public override string Description =>
        "List curated Azure Red Hat OpenShift (ARO) public documentation from Azure Learn and Red Hat docs. Supports optional provider and topic filters.";

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
        command.Options.Add(AroOptionDefinitions.Provider);
        command.Options.Add(AroOptionDefinitions.Topic);

        command.Validators.Add(commandResult =>
        {
            var provider = commandResult.GetValueOrDefault(AroOptionDefinitions.Provider);
            if (!string.IsNullOrWhiteSpace(provider) &&
                provider is not "all" and not "azure" and not "redhat")
            {
                commandResult.AddError("Invalid --provider value. Allowed values: all, azure, redhat.");
            }
        });
    }

    protected override DocumentationListOptions BindOptions(ParseResult parseResult)
    {
        var options = base.BindOptions(parseResult);
        options.Provider = parseResult.CommandResult.GetValueOrDefault(AroOptionDefinitions.Provider);
        options.Topic = parseResult.CommandResult.GetValueOrDefault(AroOptionDefinitions.Topic);
        return options;
    }

    public override Task<CommandResponse> ExecuteAsync(CommandContext context, ParseResult parseResult, CancellationToken cancellationToken)
    {
        if (!Validate(parseResult.CommandResult, context.Response).IsValid)
        {
            return Task.FromResult(context.Response);
        }

        var options = BindOptions(parseResult);

        try
        {
            var provider = (options.Provider ?? "all").Trim().ToLowerInvariant();
            var topic = options.Topic?.Trim();

            IEnumerable<Models.PublicDocument> query = Catalog;

            if (provider != "all")
            {
                query = query.Where(d => string.Equals(d.Provider, provider, StringComparison.OrdinalIgnoreCase));
            }

            if (!string.IsNullOrWhiteSpace(topic))
            {
                query = query.Where(d =>
                    d.Title.Contains(topic, StringComparison.OrdinalIgnoreCase) ||
                    d.Category.Contains(topic, StringComparison.OrdinalIgnoreCase) ||
                    d.Description.Contains(topic, StringComparison.OrdinalIgnoreCase) ||
                    d.Url.Contains(topic, StringComparison.OrdinalIgnoreCase));
            }

            var results = query.OrderBy(d => d.Provider).ThenBy(d => d.Category).ThenBy(d => d.Title).ToList();
            context.Response.Results = ResponseResult.Create(new DocumentationListCommandResult(results), AroJsonContext.Default.DocumentationListCommandResult);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error listing ARO public documentation. Provider: {Provider}, Topic: {Topic}", options.Provider, options.Topic);
            HandleException(context, ex);
        }

        return Task.FromResult(context.Response);
    }

    internal record DocumentationListCommandResult(List<Models.PublicDocument> Documents);
}
