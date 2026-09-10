# Deterministic xUnit test-project recipe

Use this recipe only when the approved plan creates a new xUnit project. Existing repository conventions always take precedence.

## Required decisions before approval

- Name one exact test-project path and one exact target framework.
- Record exact approved versions for `Microsoft.NET.Test.Sdk`, `xunit`, and `xunit.runner.visualstudio` in the schema-version-2 execution contract.
- Name the production `ProjectReference`, test levels, fake/mock strategy, and every expected file.
- Reuse a unique configured `.sln` or `.slnx` target for restore, build, and test.

## Project contract

The test project must set `IsTestProject` and `IsPackable`, expose xUnit globally, and keep the runner private:

```xml
<PropertyGroup>
  <TargetFramework>net8.0</TargetFramework>
  <ImplicitUsings>enable</ImplicitUsings>
  <Nullable>enable</Nullable>
  <IsPackable>false</IsPackable>
  <IsTestProject>true</IsTestProject>
</PropertyGroup>
<ItemGroup>
  <Using Include="Xunit" />
</ItemGroup>
<ItemGroup>
  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="APPROVED_VERSION" />
  <PackageReference Include="xunit" Version="APPROVED_VERSION" />
  <PackageReference Include="xunit.runner.visualstudio" Version="APPROVED_VERSION">
    <PrivateAssets>all</PrivateAssets>
    <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
  </PackageReference>
</ItemGroup>
```

Do not copy placeholder framework or package versions. Use only versions frozen in the approved execution contract.

## Root SDK project guard

An SDK-style production project located at repository root can recursively compile test `.cs` files placed below it. When the approved test project is nested under that root, modify the production project in the same plan and exclude the exact test subtree before default items are evaluated:

```xml
<DefaultItemExcludes>$(DefaultItemExcludes);ClientsApiTest.Tests/**</DefaultItemExcludes>
```

Use the actual approved relative directory. Do not use a broad `tests/**` exclusion unless that entire directory is intentionally reserved for tests.

## Solution registration

Prefer the managed `workflow_dotnet_solution_add` operation or its exact `add-dotnet-project.ps1` fallback after `BeginImplementation`. Do not hand-author solution GUIDs and do not request general shell access.

## Pre-gate static check

Before invoking the deterministic gate, confirm from the written files that:

- xUnit attributes and assertions resolve through `<Using Include="Xunit" />` or an approved `global using Xunit;` file;
- the root production project excludes the nested test subtree when applicable;
- the test project references the intended production project;
- every created or modified file is listed in the frozen execution contract.
