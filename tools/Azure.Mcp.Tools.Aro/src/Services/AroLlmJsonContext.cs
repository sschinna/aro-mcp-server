// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using System.Text.Json.Serialization;

namespace Azure.Mcp.Tools.Aro.Services;

[JsonSerializable(typeof(Models.Cluster))]
[JsonSerializable(typeof(Models.ClusterProfile))]
[JsonSerializable(typeof(Models.ConsoleProfile))]
[JsonSerializable(typeof(Models.ApiServerProfile))]
[JsonSerializable(typeof(Models.NetworkProfile))]
[JsonSerializable(typeof(Models.MasterProfile))]
[JsonSerializable(typeof(Models.WorkerProfile))]
[JsonSerializable(typeof(Models.IngressProfile))]
[JsonSerializable(typeof(Models.ServicePrincipalProfile))]
[JsonSerializable(typeof(Models.LoadBalancerProfile))]
[JsonSerializable(typeof(Models.ManagedOutboundIps))]
[JsonSerializable(typeof(Models.EffectiveOutboundIp))]
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    WriteIndented = true)]
internal sealed partial class AroLlmJsonContext : JsonSerializerContext;
