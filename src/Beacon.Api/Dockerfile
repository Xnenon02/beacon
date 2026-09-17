# Stage 1: build the app with the full SDK.
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG PROJECT=src/Beacon.Api/Beacon.Api.csproj
WORKDIR /src
COPY . .
RUN dotnet restore ./$PROJECT
RUN dotnet publish ./$PROJECT \
  --configuration Release \
  --output /app/publish

# Stage 2: run the app with the runtime only. No SDK, no source code.
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "Beacon.Api.dll"]
