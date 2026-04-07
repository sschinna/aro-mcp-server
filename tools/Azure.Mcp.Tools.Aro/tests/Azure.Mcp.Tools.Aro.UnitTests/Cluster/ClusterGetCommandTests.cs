// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using Azure.Mcp.Core.Options;
using Azure.Mcp.Tools.Aro.Commands.Cluster;
using Azure.Mcp.Tools.Aro.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Mcp.Core.Models.Command;
using NSubstitute;
using Xunit;

namespace Azure.Mcp.Tools.Aro.UnitTests.Cluster;

public class ClusterGetCommandTests
{
    [Fact]
    public void Constructor_InitializesCommandCorrectly()
    {
        var aroService = Substitute.For<IAroService>();
        var logger = Substitute.For<ILogger<ClusterGetCommand>>();
        var command = new ClusterGetCommand(logger, aroService);

        Assert.Equal("get", command.Name);
        Assert.NotNull(command.Description);
    }

    [Theory]
    [InlineData("--subscription sub1 --resource-group rg1 --cluster cluster1", true)]
    [InlineData("--subscription sub1 --resource-group rg1", true)]
    [InlineData("--subscription sub1 --allow-subscription-enumeration", true)]
    [InlineData("--subscription sub1 --cluster cluster1", false)]
    [InlineData("--subscription sub1", false)]
    public async Task ExecuteAsync_ValidatesInputCorrectly(string args, bool shouldSucceed)
    {
        var aroService = Substitute.For<IAroService>();
        var logger = Substitute.For<ILogger<ClusterGetCommand>>();
        var command = new ClusterGetCommand(logger, aroService);

        if (shouldSucceed)
        {
            aroService.GetClusters(
                Arg.Any<string>(),
                Arg.Any<string?>(),
                Arg.Any<string>(),
                Arg.Any<string?>(),
                Arg.Any<RetryPolicyOptions>(),
                Arg.Any<CancellationToken>())
                .Returns([]);
        }

        var context = new CommandContext(new ServiceCollection().BuildServiceProvider());
        var parseResult = command.GetCommand().Parse(args);
        var response = await command.ExecuteAsync(context, parseResult, TestContext.Current.CancellationToken);

        Assert.Equal(shouldSucceed ? System.Net.HttpStatusCode.OK : System.Net.HttpStatusCode.BadRequest, response.Status);
    }

    [Fact]
    public async Task ExecuteAsync_ListClustersWithExplicitOptIn_ReturnsAllClusters()
    {
        var aroService = Substitute.For<IAroService>();
        var logger = Substitute.For<ILogger<ClusterGetCommand>>();
        var command = new ClusterGetCommand(logger, aroService);

        var expectedClusters = new List<Models.Cluster>
        {
            new() { Name = "cluster1", Location = "eastus" },
            new() { Name = "cluster2", Location = "westus" }
        };

        aroService.GetClusters(
            "sub1",
            Arg.Any<string?>(),
            Arg.Any<string?>(),
            Arg.Any<string?>(),
            Arg.Any<RetryPolicyOptions>(),
            Arg.Any<CancellationToken>())
            .Returns(expectedClusters);

        var context = new CommandContext(new ServiceCollection().BuildServiceProvider());
        var parseResult = command.GetCommand().Parse("--subscription sub1 --allow-subscription-enumeration");
        var response = await command.ExecuteAsync(context, parseResult, TestContext.Current.CancellationToken);

        Assert.Equal(System.Net.HttpStatusCode.OK, response.Status);
    }
}
