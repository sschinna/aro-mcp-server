// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using Azure.Mcp.Tools.Aro.Commands.Documentation;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Mcp.Core.Models.Command;
using NSubstitute;
using Xunit;

namespace Azure.Mcp.Tools.Aro.UnitTests.Documentation;

public class DocumentationListCommandTests
{
    [Fact]
    public void Constructor_InitializesCommandCorrectly()
    {
        var logger = Substitute.For<ILogger<DocumentationListCommand>>();
        var command = new DocumentationListCommand(logger);

        Assert.Equal("list", command.Name);
        Assert.NotNull(command.Description);
    }

    [Theory]
    [InlineData("--subscription sub1", true)]
    [InlineData("--subscription sub1 --provider azure", true)]
    [InlineData("--subscription sub1 --provider redhat", true)]
    [InlineData("--subscription sub1 --provider all --topic networking", true)]
    [InlineData("--subscription sub1 --provider invalid", false)]
    public async Task ExecuteAsync_ValidatesInputCorrectly(string args, bool shouldSucceed)
    {
        var logger = Substitute.For<ILogger<DocumentationListCommand>>();
        var command = new DocumentationListCommand(logger);

        var context = new CommandContext(new ServiceCollection().BuildServiceProvider());
        var parseResult = command.GetCommand().Parse(args);
        var response = await command.ExecuteAsync(context, parseResult, TestContext.Current.CancellationToken);

        Assert.Equal(shouldSucceed ? System.Net.HttpStatusCode.OK : System.Net.HttpStatusCode.BadRequest, response.Status);
    }
}
