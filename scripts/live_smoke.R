# Explicit live check: one model call and disposable synthetic Supabase records.
if(.Platform$OS.type=="windows")suppressWarnings(Sys.setlocale("LC_CTYPE","English_United States.utf8"))
if(dir.exists(".r-library")) .libPaths(c(normalizePath(".r-library"),.libPaths()))
if(file.exists(".Renviron"))readRenviron(".Renviron")
for(f in c("core","retrieval","storage","ai"))source(paste0("modules/",f,".R"),encoding="UTF-8")
cfg<-app_config()
if(!cfg$ai_enabled||cfg$storage!="supabase"||cfg$mode!="public")stop("Configure the public model and Supabase settings first. No live test was run.",call.=FALSE)
corpus<-load_corpus();search_index<-build_search(corpus)
read_test_rows<-function(sid){
  h<-curl::new_handle()
  curl::handle_setopt(h,timeout=15,connecttimeout=10,followlocation=FALSE)
  curl::handle_setheaders(h,.list=supabase_headers(cfg))
  r<-curl::curl_fetch_memory(paste0(cfg$supabase_url,"/rest/v1/wwc_events?select=event_id&session_id=eq.",sid),h)
  if(r$status_code!=200L)stop("Could not verify the test records.",call.=FALSE)
  jsonlite::fromJSON(rawToChar(r$content),simplifyVector=FALSE)
}
run_live_check<-function(){
  stopifnot(storage_probe(cfg))
  sid<-new_id()
  on.exit(tryCatch(delete_session_data(cfg,sid),error=function(e)warning("Could not remove this script's synthetic test records; inspect phase=system_test.")),add=TRUE)
  event<-list(event_id=new_id(),session_id=sid,sequence=1L,timestamp_utc=utc_now(),type="deployment_smoke_test",
    app_version="0.3.1",corpus_version=corpus$corpus_version,consented=TRUE,
    consent_version="system-test-no-human-data",phase="system_test",payload=list(synthetic=TRUE))
  stopifnot(persist_event(cfg,event),persist_event(cfg,event),length(read_test_rows(sid))==1L)
  stopifnot(delete_session_data(cfg,sid),length(read_test_rows(sid))==0L)
  cat("PASS: live Supabase probe, write/read, idempotence and deletion of this script's test session.\n")
  retrieval<-retrieve_context(corpus,search_index,"multisyllabic decoding",pinned="G22-R1",grade="4")
  request<-build_ai_request("Explain this practice and suggest one next step for a Grade 4 small group. Clearly distinguish the guide from your adaptation.",
    list(),list(grade="4",setting="Small group"),retrieval,cfg)
  if(!reserve_ai_call(cfg))stop("Today's AI allowance is unavailable.",call.=FALSE)
  result<-perform_ai_request(request,cfg)
  result$answer<-validate_ai_response(result$answer,retrieval)
  dir.create("private",showWarnings=FALSE)
  jsonlite::write_json(list(checked_at=utc_now(),synthetic_test=TRUE,result=result,retrieval=retrieval),
    "private/live-smoke-result.json",pretty=TRUE,auto_unbox=TRUE,null="null")
  cat("PASS: one live model response passed structural and source-quote checks.\n")
  cat("Review private/live-smoke-result.json against the supplied sources before accepting answer quality. This is not a full production or research validation.\n")
}
run_live_check()
