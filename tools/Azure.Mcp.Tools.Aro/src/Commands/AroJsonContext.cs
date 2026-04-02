// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using System.Text.Json.Serialization;
using Azure.Mcp.Tools.Aro.Commands.Cluster;
using Azure.Mcp.Tools.Aro.Services;

namespace Azure.Mcp.Tools.Aro.Commands;

[JsonSerializable(typeof(ClusterGetCommand.ClusterGetCommandResult))]
[JsonSerializable(typeof(Models.Cluster))]
[JsonSerializable(typeof(Models.ClusterProfile))]
[JsonSerializable(typeof(Models.ConsoleProfile))]
[JsonSerializable(typeof(Models.ApiServerProfile))]
[JsonSerializable(typeof(Models.NetworkProfile))]
[JsonSerializable(typeof(Models.MasterProfile))]
[JsonSerializable(typeof(Models.WorkerProfile))]
[JsonSerializable(typeof(Models.IngressProfile))]
[JsonSerializable(typeof(Models.ServicePrincipalProfile))]
[JsonSerializable(typeof(AroClusterProperties))]
[JsonSerializable(typeof(AroServicePrincipalProperties))]
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class AroJsonContext : JsonSerializerContext;

[JsonSerializable(typeof(AroClusterProperties))]
[JsonSerializable(typeof(AroServicePrincipalProperties))]
[JsonSerializable(typeof(Models.ClusterProfile))]
[JsonSerializable(typeof(Models.ConsoleProfile))]
[JsonSerializable(typeof(Models.ApiServerProfile))]
[JsonSerializable(typeof(Models.NetworkProfile))]
[JsonSerializable(typeof(Models.MasterProfile))]
[JsonSerializable(typeof(Models.WorkerProfile))]
[JsonSerializable(typeof(Models.IngressProfile))]
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class AroPropertiesJsonContext : JsonSerializerContext;
