using './security.bicep'

param vaultName = 'kv-clo25-namn-we'
param appName = 'app-clo25-namn-we'
param deployerObjectId = 'a1a812b8-cd2b-4200-abec-261ca25ea638'

// The secret is read from an environment variable at deploy time.
// The deploy stops with BCP427 if the variable has not been set.
param secretValue = readEnvironmentVariable('SECRET_VALUE')
