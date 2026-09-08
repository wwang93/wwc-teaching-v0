# Offline compatibility check: no environment file, network, or actual credentials.
source("modules/core.R",encoding="UTF-8")
source("modules/storage.R",encoding="UTF-8")
Sys.setenv(WWC_APP_MODE="local",WWC_STORAGE_BACKEND="supabase",WWC_RESEARCH_ENABLED="false",
  SUPABASE_URL="https://example.supabase.co",SUPABASE_SECRET_KEY="sb_secret_fixture",SUPABASE_SERVICE_ROLE_KEY="legacy-jwt-fixture")
cfg<-app_config()
stopifnot(cfg$supabase_key=="sb_secret_fixture")
seen<-NULL
post_json<-function(url,body,headers=list(),timeout=45){seen<<-list(url=url,body=body,headers=headers);TRUE}
stopifnot(storage_probe(cfg),identical(names(seen$headers),"apikey"),seen$headers$apikey=="sb_secret_fixture")
Sys.unsetenv("SUPABASE_SECRET_KEY");cfg<-app_config()
stopifnot(cfg$supabase_key=="legacy-jwt-fixture",storage_probe(cfg),
  seen$headers$Authorization=="Bearer legacy-jwt-fixture",seen$headers$apikey=="legacy-jwt-fixture")
cat("PASS: new secret-key precedence and apikey-only requests; legacy JWT fallback and bearer header. No live service used.\n")
