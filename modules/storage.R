open_local_db <- function(cfg) {
  dir.create(dirname(cfg$db_path), recursive = TRUE, showWarnings = FALSE)
  con <- DBI::dbConnect(RSQLite::SQLite(), cfg$db_path)
  DBI::dbExecute(con, "PRAGMA busy_timeout=5000")
  DBI::dbExecute(con, "CREATE TABLE IF NOT EXISTS events (event_id TEXT PRIMARY KEY, session_id TEXT NOT NULL, timestamp_utc TEXT NOT NULL, event_type TEXT NOT NULL, body TEXT NOT NULL)")
  DBI::dbExecute(con, "CREATE TABLE IF NOT EXISTS ai_budget (day TEXT PRIMARY KEY, calls INTEGER NOT NULL)")
  con
}
supabase_headers <- function(cfg) {
  headers <- list(apikey = cfg$supabase_key)
  # New secret keys are opaque API keys, not JWT bearer tokens.
  if (!startsWith(cfg$supabase_key, "sb_secret_"))
    headers$Authorization <- paste("Bearer", cfg$supabase_key)
  headers
}
supabase_rpc <- function(cfg, name, args) {
  post_json(paste0(cfg$supabase_url, "/rest/v1/rpc/", name), args,
    headers = supabase_headers(cfg), timeout = 12)
}
persist_event <- function(cfg, event) {
  stopifnot(isTRUE(event$consented), nzchar(event$consent_version), nzchar(event$session_id))
  if (cfg$storage == "supabase") return(isTRUE(supabase_rpc(cfg, "wwc_append_event", list(p_event = event))))
  con <- open_local_db(cfg); on.exit(DBI::dbDisconnect(con))
  DBI::dbExecute(con, "INSERT OR IGNORE INTO events VALUES (?, ?, ?, ?, ?)",
    params = list(event$event_id, event$session_id, event$timestamp_utc, event$type, json(event)))
  TRUE
}
delete_session_data <- function(cfg, session_id) {
  if (cfg$storage == "supabase") return(isTRUE(supabase_rpc(cfg, "wwc_delete_session", list(p_session_id = session_id))))
  con <- open_local_db(cfg); on.exit(DBI::dbDisconnect(con))
  DBI::dbExecute(con, "DELETE FROM events WHERE session_id = ?", params = list(session_id))
  TRUE
}
reserve_ai_call <- function(cfg) {
  if (cfg$storage == "supabase") return(isTRUE(supabase_rpc(cfg, "wwc_reserve_ai_call", list(p_limit = cfg$daily_limit))))
  con <- open_local_db(cfg); on.exit(DBI::dbDisconnect(con))
  day <- format(Sys.time(), "%Y-%m-%d", tz = "UTC")
  DBI::dbWithTransaction(con, {
    DBI::dbExecute(con, "INSERT OR IGNORE INTO ai_budget VALUES (?, 0)", params = list(day))
    n <- DBI::dbExecute(con, "UPDATE ai_budget SET calls=calls+1 WHERE day=? AND calls<?", params = list(day, cfg$daily_limit))
    n == 1L
  })
}
storage_probe <- function(cfg) {
  if (cfg$storage == "supabase") return(isTRUE(supabase_rpc(cfg, "wwc_storage_ready", list())))
  con <- open_local_db(cfg); on.exit(DBI::dbDisconnect(con)); TRUE
}
