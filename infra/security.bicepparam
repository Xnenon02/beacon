using './security.bicep'

param vaultName = 'kv-clo25-namn-we'
param appName = 'app-clo25-namn-we'

// Both values are read from environment variables at deploy time, so nothing
// personal or secret is committed. The deploy stops with BCP427 if one is unset.
//   DEPLOYER_OBJECT_ID: az ad signed-in-user show --query id --output tsv
//   SECRET_VALUE:       the secret itself (the tutorial shows how to read it
//                       without it ending up in shell history)
param deployerObjectId = readEnvironmentVariable('DEPLOYER_OBJECT_ID')
param secretValue = readEnvironmentVariable('SECRET_VALUE')
