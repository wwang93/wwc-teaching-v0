if(dir.exists(".r-library")) .libPaths(c(normalizePath(".r-library"),.libPaths()))
if(!requireNamespace("rsconnect",quietly=TRUE)) stop("Run install.R or install.packages('rsconnect') first.")
Sys.setenv(RENV_PATHS_ROOT=file.path(tempdir(),"wwc-renv"),RENV_CONFIG_CACHE_ENABLED="FALSE")
files<-c("app.R","DESCRIPTION",".Rbuildignore",list.files("modules",full.names=TRUE,recursive=TRUE),
  "data/actions.json","data/passages.json","data/catalog.json",list.files("www",full.names=TRUE,recursive=TRUE))
stopifnot(!any(grepl("private|Renviron|\\.env|rsconnect",files)))
rsconnect::writeManifest(appDir=".",appFiles=files,appPrimaryDoc="app.R")
cat("manifest.json created from the application files only. No keys or session data included.\n")
