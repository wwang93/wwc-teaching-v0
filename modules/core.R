`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x
scalar_text <- function(x, max_chars = 6000L) {
  if (!is.character(x) || length(x) != 1L || is.na(x)) return("")
  substr(trimws(x), 1L, max_chars)
}
utc_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
new_id <- function() uuid::UUIDgenerate()
json <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
named_by <- function(x, key) setNames(x, vapply(x, function(a) a[[key]], ""))
env_int <- function(name, default, low = 1L, high = 10000L) {
  x <- suppressWarnings(as.integer(Sys.getenv(name, default)))
  if (is.na(x) || x < low || x > high) stop(paste("Invalid configuration:", name), call. = FALSE)
  x
}
app_config <- function() {
  server_key <- Sys.getenv("SUPABASE_SECRET_KEY")
  if (!nzchar(server_key)) server_key <- Sys.getenv("SUPABASE_SERVICE_ROLE_KEY")
  cfg <- list(mode = Sys.getenv("WWC_APP_MODE", "local"),
    api_key = Sys.getenv("OPENAI_API_KEY"), model = Sys.getenv("WWC_AI_MODEL"),
    storage = Sys.getenv("WWC_STORAGE_BACKEND", "sqlite"),
    db_path = Sys.getenv("WWC_SQLITE_PATH", "private/wwc.sqlite"),
    supabase_url = sub("/+$", "", Sys.getenv("SUPABASE_URL")),
    supabase_key = server_key,
    session_limit = env_int("WWC_AI_SESSION_LIMIT", 15, high = 100),
    daily_limit = env_int("WWC_AI_DAILY_LIMIT", 150),
    max_output_tokens = env_int("WWC_AI_MAX_OUTPUT_TOKENS", 1800, low = 500, high = 4000),
    research_enabled = identical(Sys.getenv("WWC_RESEARCH_ENABLED", "false"), "true"),
    consent_version = Sys.getenv("WWC_CONSENT_VERSION", "product-feedback-v1"),
    consent_text = Sys.getenv("WWC_CONSENT_TEXT", "If you opt in, we will save your questions, AI replies, sources you open, and plan decisions to improve this application. Do not include student names or identifying details. You can stop recording or delete this session's saved data below. Browsing and AI use are available without opting in."))
  stopifnot(cfg$mode %in% c("local", "public"), cfg$storage %in% c("sqlite", "supabase"))
  cfg$ai_enabled <- nzchar(cfg$api_key) && nzchar(cfg$model)
  if (cfg$storage == "supabase" && (!grepl("^https://[a-zA-Z0-9.-]+$", cfg$supabase_url) || !nzchar(cfg$supabase_key)))
    stop("Configure SUPABASE_URL and SUPABASE_SECRET_KEY (or legacy SUPABASE_SERVICE_ROLE_KEY) on the server.", call. = FALSE)
  if (cfg$mode == "public" && (!cfg$ai_enabled || cfg$storage != "supabase"))
    stop("Public release requires a model API configuration and Supabase persistence. Run scripts/preflight.R.", call. = FALSE)
  if (cfg$research_enabled && (!nzchar(Sys.getenv("WWC_CONSENT_TEXT")) || !nzchar(Sys.getenv("WWC_CONSENT_VERSION"))))
    stop("Research mode requires the configured study consent text and version.", call. = FALSE)
  cfg
}

load_corpus <- function() {
  c <- jsonlite::read_json("data/actions.json", simplifyVector = FALSE)
  c$guides <- named_by(c$guides, "guide_id")
  c$actions <- named_by(c$actions, "action_id")
  c$passages <- named_by(jsonlite::read_json("data/passages.json", simplifyVector = FALSE), "source_id")
  stopifnot(length(c$guides) == 30L, length(c$actions) == 165L)
  for (a in c$actions) stopifnot(a$guide_id %in% names(c$guides),
    all(unlist(a$page_ids) %in% names(c$passages)), a$evidence_source_id %in% names(c$passages))
  c
}

post_json <- function(url, body, headers = list(), timeout = 45) {
  h <- curl::new_handle()
  payload <- if (is.list(body) && !length(body)) "{}" else json(body)
  curl::handle_setopt(h, postfields = payload, timeout = timeout, connecttimeout = 10,
    followlocation = FALSE)
  curl::handle_setheaders(h, .list = c(list("Content-Type" = "application/json"), headers))
  r <- curl::curl_fetch_memory(url, h)
  # Never surface provider response bodies, request headers or secrets in the UI/logs.
  if (r$status_code < 200 || r$status_code >= 300)
    stop(sprintf("Service request failed (HTTP %s).", r$status_code), call. = FALSE)
  if (!length(r$content)) return(NULL)
  jsonlite::fromJSON(rawToChar(r$content), simplifyVector = FALSE)
}
