if (.Platform$OS.type=="windows") suppressWarnings(Sys.setlocale("LC_CTYPE","English_United States.utf8"))
Sys.setenv(WWC_APP_MODE="local",WWC_STORAGE_BACKEND="sqlite",WWC_SQLITE_PATH=tempfile(fileext=".sqlite"),OPENAI_API_KEY="",WWC_AI_MODEL="",WWC_RESEARCH_ENABLED="false")
# Isolated test process: never load a developer's real .Renviron credentials.
readRenviron<-function(file)invisible(TRUE)
source("app.R",encoding="UTF-8")
cfg$ai_enabled<-TRUE;cfg$model<-"test-fixture-only";cfg$api_key<-"test-placeholder";cfg$daily_limit<-30L
# Mock only the HTTP boundary in this isolated test process. The actual asynchronous
# request/parser/validator/UI path runs unchanged; no fake provider is in the app.
post_json<-function(url,body,headers=list(),timeout=45){
  d<-jsonlite::fromJSON(body$input,simplifyVector=FALSE);s<-d$current_retrieval$sources[[1]]
  a<-list(overview=paste("Test fixture, previous turns:",length(d$previous_turns)),
    blocks=list(list(kind="source_guidance",text="Inspect this source before adapting the practice.",sources=list(list(source_id=s$source_id,quote=substr(s$text,1,90)))),
      list(kind="adaptation",text="Discuss one next step for your setting.",sources=list())),
    action_ids=list(d$current_retrieval$action_ids[[1]]),follow_up="What would you change?",plan_text="A test-only plan for editing.")
  if(identical(d$question,"Test invalid citation"))a$blocks[[1]]$sources[[1]]$source_id<-"fabricated-source"
  list(id="test-response",status="completed",model="test-fixture-only",usage=list(input_tokens=100,output_tokens=60),
    output=list(list(content=list(list(type="output_text",text=json(a))))))
}
future::plan(future::multisession,workers=I(1L))
retrieval_test<-retrieve_context(corpus,search_index,"decoding",pinned="G22-R1")
request_test<-build_ai_request("Explain",list(),list(),retrieval_test,cfg)
direct<-perform_ai_request(request_test,cfg)
stopifnot(!is.null(validate_ai_response(direct$answer,retrieval_test)))
f<-future::future(perform_ai_request(request_test,cfg),globals=list(request_test=request_test,cfg=cfg,
  perform_ai_request=perform_ai_request,post_json=post_json,json=json,`%||%`=`%||%`),packages=c("curl","jsonlite"),seed=TRUE)
tryCatch({rr<-future::value(f);cat("Worker fixture parsed successfully\n")},error=function(e)stop(paste("Test worker:",conditionMessage(e))))
shiny::testServer(server,{
  session$setInputs(record_consent=FALSE)
  choose_action("G22-R1");session$flushReact()
  session$setInputs(send_request=list(question="Explain this decoding practice",context="Grade 4",nonce=1))
  deadline<-Sys.time()+25
  while(isolate(busy())&&Sys.time()<deadline){later::run_now(0.05);Sys.sleep(0.05);session$flushReact()}
  if(length(history())!=1L)cat("Test chat state:",chat_error(),"\n")
  stopifnot(!busy(),length(history())==1L,is.null(chat_error()),length(events())==0L)
  stopifnot(grepl("From the guide",output$conversation$html,fixed=TRUE),grepl("Suggested adaptation",output$conversation$html,fixed=TRUE))
  session$setInputs(send_request=list(question="How could I adapt it?",context="Grade 4, small group",nonce=2))
  deadline<-Sys.time()+25
  while(isolate(busy())&&Sys.time()<deadline){later::run_now(0.05);Sys.sleep(0.05);session$flushReact()}
  stopifnot(length(history())==2L,grepl("previous turns: 1",history()[[2]]$response$overview,fixed=TRUE))
  session$setInputs(ui_event=list(type="apply_plan",source="2",nonce=3))
  choose_action("G25-R1");session$flushReact()
  session$setInputs(ui_event=list(type="apply_plan",source="2",nonce=4))
  stopifnot(is.null(saved_plans()[["G25-R1"]]))
  # Consent given during a request must not retroactively record that request/answer.
  session$setInputs(send_request=list(question="A question before consent",context="Grade 4",nonce=5))
  session$setInputs(record_consent=TRUE)
  deadline<-Sys.time()+25
  while(isolate(busy())&&Sys.time()<deadline){later::run_now(0.05);Sys.sleep(0.05);session$flushReact()}
  stopifnot(length(history())==3L,!any(vapply(events(),function(e)e$type," ") %in% c("ai_question","ai_answer_displayed")))
  # Rejected model output must never enter the visible conversation.
  session$setInputs(send_request=list(question="Test invalid citation",context="Grade 4",nonce=6))
  deadline<-Sys.time()+25
  while(isolate(busy())&&Sys.time()<deadline){later::run_now(0.05);Sys.sleep(0.05);session$flushReact()}
  stopifnot(length(history())==3L,grepl("source checks",chat_error(),fixed=TRUE),any(vapply(events(),function(e)e$type,"")=="ai_answer_rejected"))
  # A reply to a cleared conversation must not reappear in the new one.
  session$setInputs(send_request=list(question="Explain this practice",context="Grade 4",nonce=7))
  session$setInputs(clear_chat=1)
  deadline<-Sys.time()+25
  while(isolate(busy())&&Sys.time()<deadline){later::run_now(0.05);Sys.sleep(0.05);session$flushReact()}
  stopifnot(!busy(),length(history())==0L)
})
future::plan(future::sequential)
cat("PASS: asynchronous provider boundary, response parsing, validated rendering, two-turn context, no unconsented writes, and plan/action isolation. This used a test HTTP fixture, not a live model.\n")
