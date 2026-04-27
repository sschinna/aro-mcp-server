// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using System.ClientModel;
using System.Text;
using System.Text.Json;
using Azure.AI.OpenAI;
using Azure.Identity;
using Azure.Mcp.Tools.Aro.Models;
using Microsoft.Extensions.Logging;
using OpenAI.Chat;

namespace Azure.Mcp.Tools.Aro.Services;

public sealed class LlmService : ILlmService
{
    private readonly ChatClient _chatClient;
    private readonly ILogger<LlmService> _logger;

    public LlmService(ILogger<LlmService> logger)
    {
        _logger = logger;

        var endpoint = Environment.GetEnvironmentVariable("AZURE_OPENAI_ENDPOINT")
            ?? "https://eastus2.api.cognitive.microsoft.com/";
        var deploymentName = Environment.GetEnvironmentVariable("AZURE_OPENAI_DEPLOYMENT")
            ?? "gpt-4o";

        var client = new AzureOpenAIClient(
            new Uri(endpoint),
            new DefaultAzureCredential());

        _chatClient = client.GetChatClient(deploymentName);
    }

    public async Task<string> DiagnoseClusterAsync(
        Cluster cluster, string question, CancellationToken cancellationToken = default)
    {
        var clusterJson = SerializeCluster(cluster);

        var messages = new List<ChatMessage>
        {
            new SystemChatMessage(
                """
                You are an Azure Red Hat OpenShift (ARO) expert. You diagnose cluster issues
                based on the cluster configuration and status data provided. Give concise,
                actionable answers. Reference specific fields from the cluster data when relevant.
                If the data is insufficient to answer, say so and suggest what additional
                information would help.
                """),
            new UserChatMessage(
                $"""
                Here is the ARO cluster data:

                ```json
                {clusterJson}
                ```

                Question: {question}
                """)
        };

        var options = new ChatCompletionOptions { Temperature = 0.3f, MaxOutputTokenCount = 1024 };

        _logger.LogInformation("Sending diagnosis request to Azure OpenAI for cluster {ClusterName}", cluster.Name);

        ClientResult<ChatCompletion> result = await _chatClient.CompleteChatAsync(
            messages, options, cancellationToken);

        return result.Value.Content[0].Text;
    }

    public async Task<string> SummarizeClusterAsync(
        Cluster cluster, CancellationToken cancellationToken = default)
    {
        var clusterJson = SerializeCluster(cluster);

        var messages = new List<ChatMessage>
        {
            new SystemChatMessage(
                """
                You are an Azure Red Hat OpenShift (ARO) expert. Summarize the cluster status
                in a clear, structured format. Include: overall health assessment, key configuration
                details (version, visibility, node sizes, network config), and any potential
                concerns or recommendations. Keep it concise but comprehensive.
                """),
            new UserChatMessage(
                $"""
                Summarize this ARO cluster:

                ```json
                {clusterJson}
                ```
                """)
        };

        var options = new ChatCompletionOptions { Temperature = 0.3f, MaxOutputTokenCount = 1024 };

        _logger.LogInformation("Sending summary request to Azure OpenAI for cluster {ClusterName}", cluster.Name);

        ClientResult<ChatCompletion> result = await _chatClient.CompleteChatAsync(
            messages, options, cancellationToken);

        return result.Value.Content[0].Text;
    }

    private static string SerializeCluster(Cluster cluster)
    {
        return JsonSerializer.Serialize(cluster, AroLlmJsonContext.Default.Cluster);
    }
}
