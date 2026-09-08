# Run from the application directory. This reports presence, never secret values.
if (.Platform$OS.type=="windows") suppressWarnings(Sys.setlocale("LC_CTYPE","English_United States.utf8"))
if (dir.exists(".r-library")) .libPaths(c(normalizePath(".r-library"),.libPaths()))
if (file.exists(".Renviron")) readRenviron(".Renviron")
source("modules/core.R",encoding="UTF-8")
source("modules/storage.R",encoding="UTF-8")
key_name<-if(nzchar(Sys.getenv("SUPABASE_SECRET_KEY")))"SUPABASE_SECRET_KEY" else "SUPABASE_SERVICE_ROLE_KEY"
needed<-c("OPENAI_API_KEY","WWC_AI_MODEL","SUPABASE_URL",key_name)
ready<-vapply(needed,function(x)nzchar(Sys.getenv(x)),TRUE)
for(n in needed)cat(n,if(ready[[n]])"configured" else "MISSING","\n")
if(!ready[[key_name]])cat("Use SUPABASE_SECRET_KEY for a new sb_secret_ key; the legacy variable also remains supported.\n")
cat("WWC_APP_MODE",Sys.getenv("WWC_APP_MODE","local"),"\n")
cat("WWC_STORAGE_BACKEND",Sys.getenv("WWC_STORAGE_BACKEND","sqlite"),"\n")
if(all(ready)){
  c<-tryCatch(app_config(),error=function(e)NULL)
  ok<-!is.null(c)&&c$mode=="public"&&c$storage=="supabase"&&tryCatch(storage_probe(c),error=function(e)FALSE)
  cat("Public service configuration:",if(ok)"ready for live smoke test" else "not ready; check mode and Supabase SQL setup","\n")
}else cat("Public deployment is not configured. Local content browsing and plan editing remain available.\n")
