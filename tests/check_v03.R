if (.Platform$OS.type == "windows") suppressWarnings(Sys.setlocale("LC_CTYPE","English_United States.utf8"))
Sys.setenv(WWC_APP_MODE="local",WWC_STORAGE_BACKEND="sqlite",WWC_SQLITE_PATH=tempfile(fileext=".sqlite"),WWC_AI_MODEL="",OPENAI_API_KEY="",WWC_RESEARCH_ENABLED="false")
# Isolated test process: never load a developer's real .Renviron credentials.
readRenviron<-function(file)invisible(TRUE)
source("app.R",encoding="UTF-8")
expect_error<-function(expr){ok<-inherits(tryCatch({force(expr);NULL},error=function(e)e),"error");stopifnot(ok)}
stopifnot(length(corpus$actions)==165L,length(corpus$guides)==30L,sum(vapply(corpus$actions,function(a)length(a$steps),0L))==600L)
for(a in corpus$actions){stopifnot(a$review_status=="needs_review");for(s in a$steps)for(id in s$source_ids)stopifnot(!is.null(source_entry(corpus,id,a)))}
cases<-list(
  list(q="fourth graders struggle reading multisyllabic words decoding",want="G22-R1",grade="4"),
  list(q="fractions number line",want="G12-R2",grade="all"),
  list(q="college advising academic nonacademic support",want="G21-R1",grade="Postsecondary"),
  list(q="classroom behavior expectations",want="G07-R1",grade="4"),
  list(q="worked solved problems algebra",want="G26-R1",grade="8"))
for(c in cases){found<-search_actions(corpus,search_index,c$q,grade=c$grade,limit=5L);ids<-vapply(found,function(x)x$action$action_id,"");cat(c$q,":",paste(ids,collapse=","),"\n");stopifnot(c$want %in% ids)}
stopifnot(length(search_actions(corpus,search_index,"zzzzqxvnoresult"))==0L)
retrieval<-retrieve_context(corpus,search_index,"multisyllabic decoding",pinned="G22-R1",grade="4")
s<-retrieval$sources[[1]];quote<-substr(s$text,1,80)
answer<-list(overview="Here is a starting point.",blocks=list(list(kind="source_guidance",text="Use the linked guidance.",sources=list(list(source_id=s$source_id,quote=quote)))),action_ids=list("G22-R1"),follow_up="What have you tried?",plan_text="")
stopifnot(identical(validate_ai_response(answer,retrieval),answer))
bad<-answer;bad$blocks[[1]]$sources[[1]]$source_id<-"invented";expect_error(validate_ai_response(bad,retrieval))
bad<-answer;bad$blocks[[1]]$sources[[1]]$quote<-"Made-up quote with no support";expect_error(validate_ai_response(bad,retrieval))
bad<-answer;bad$blocks[[1]]$sources<-list();expect_error(validate_ai_response(bad,retrieval))
bad<-answer;bad$action_ids<-list("G99-R1");expect_error(validate_ai_response(bad,retrieval))
request<-build_ai_request("test",list(),list(),retrieval,modifyList(cfg,list(model="configured-model")))
stopifnot(identical(request$store,FALSE),request$text$format$strict,!grepl("api_key",request$input,fixed=TRUE))
Sys.setenv(WWC_APP_MODE="public");expect_error(app_config());Sys.setenv(WWC_APP_MODE="local")
stopifnot(storage_probe(cfg))
limit_cfg<-modifyList(cfg,list(daily_limit=2L))
stopifnot(reserve_ai_call(limit_cfg),reserve_ai_call(limit_cfg),!reserve_ai_call(limit_cfg))
cat("PASS: corpus, retrieval scenarios, citation rejection, stateless model request, durable call budget.\n")

shiny::testServer(server,{
  session$setInputs(record_consent=FALSE)
  choose_action("G22-R1");stopifnot(length(events())==0L,current()$action_id=="G22-R1")
  for(id in names(corpus$actions)){
    choose_action(id);session$flushReact();stopifnot(grepl("A place to start",output$action_content$html,fixed=TRUE),
      grepl("Supporting source",output$source_content$html,fixed=TRUE))
  }
  choose_action("G22-R1");r<-as.character(revision())
  session$setInputs(teacher_context="Grade 4, 15 minutes, small group")
  pinputs<-setNames(list("Adapt","Start with a short decoding activity.","Check the source conditions."),vapply(c("decision","plan_notes","reason"),plan_field,""))
  do.call(session$setInputs,pinputs)
  session$setInputs(save_request=list(revision=r,decision="Adapt",notes="Start with a short decoding activity.",reason="Check the source conditions."))
  stopifnot(saved_plans()[["G22-R1"]]$notes=="Start with a short decoding activity.",length(events())==0L)
  saved<-saved_plans();session$setInputs(ui_event=list(type="show_source",source=current()$evidence_source_id))
  stopifnot(identical(saved,saved_plans()))
  f<-output$download_plan;stopifnot(any(grepl("Start with a short decoding activity",readLines(f),fixed=TRUE)))
  session$setInputs(export_request=list(revision=r,decision="Try",notes="A just-typed export, before input debounce.",reason="New reason",context="New context"))
  f<-output$download_plan;exported<-readLines(f)
  stopifnot(any(grepl("A just-typed export",exported,fixed=TRUE)),any(grepl("New context",exported,fixed=TRUE)))
  choose_action("G25-R1");session$setInputs(save_request=list(revision=r,decision="Try",notes="Stale content",reason="old"))
  stopifnot(is.null(saved_plans()[["G25-R1"]]))
  session$setInputs(record_consent=TRUE);stopifnot(recording(),length(events())>0L,length(pending())==0L)
  con<-open_local_db(cfg);n<-DBI::dbGetQuery(con,"select count(*) n from events where session_id=?",params=list(session_id))$n;DBI::dbDisconnect(con)
  stopifnot(n==length(events()))
  e<-events()[[1]];persist_event(cfg,e)
  con<-open_local_db(cfg);stopifnot(DBI::dbGetQuery(con,"select count(*) n from events where event_id=?",params=list(e$event_id))$n==1L);DBI::dbDisconnect(con)
  session$setInputs(record_consent=FALSE);n<-length(events());choose_action("G01-R1");stopifnot(length(events())==n)
  session$setInputs(delete_session=1);stopifnot(!recording(),length(events())==0L,length(pending())==0L)
  con<-open_local_db(cfg);stopifnot(DBI::dbGetQuery(con,"select count(*) n from events where session_id=?",params=list(session_id))$n==0L);DBI::dbDisconnect(con)
  ask("Explain the evidence");stopifnot(length(history())==0L,grepl("not connected",chat_error(),fixed=TRUE))
})
cat("PASS: every action renders, source/plan isolation, stale-save rejection, opt-in persistence, idempotence, stop/delete and missing-provider behavior.\n")

# A second independent server session cannot see the first session's work.
shiny::testServer(server,{stopifnot(length(history())==0L,length(saved_plans())==0L,length(events())==0L,!recording())})
cat("PASS: independent sessions start with isolated conversation, plans and consent.\n")
