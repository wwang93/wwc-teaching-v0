if (.Platform$OS.type == "windows") suppressWarnings(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
if (dir.exists(".r-library")) .libPaths(c(normalizePath(".r-library"), .libPaths()))
if (file.exists(".Renviron")) readRenviron(".Renviron")
library(shiny)
source("modules/core.R", local = TRUE, encoding = "UTF-8")
source("modules/retrieval.R", local = TRUE, encoding = "UTF-8")
source("modules/storage.R", local = TRUE, encoding = "UTF-8")
source("modules/ai.R", local = TRUE, encoding = "UTF-8")
APP_VERSION <- "0.3.1"
cfg <- app_config()
corpus <- load_corpus()
search_index <- build_search(corpus)
if (cfg$ai_enabled) future::plan(future::multisession, workers = 2L)
source("modules/interface.R", local = TRUE, encoding = "UTF-8")
source("modules/server.R", local = TRUE, encoding = "UTF-8")
shinyApp(ui, server)


