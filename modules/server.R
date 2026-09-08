server <- function(input,output,session) {
  session_id<-new_id()
  selected_action<-reactiveVal(NULL);selected_source<-reactiveVal(NULL);revision<-reactiveVal(0L)
  saved_plans<-reactiveVal(list());history<-reactiveVal(list());chat_error<-reactiveVal(NULL)
  export_plan<-reactiveVal(NULL)
  busy<-reactiveVal(FALSE);ai_calls<-reactiveVal(0L);chat_generation<-reactiveVal(0L)
  events<-reactiveVal(list());pending<-reactiveVal(list());storage_error<-reactiveVal(NULL);recording<-reactiveVal(FALSE)
  consented_participant_code<-reactiveVal(NULL)
  consent_epoch<-reactiveVal(0L)
  result_query<-reactiveVal(list(query="",grade="all",role="all",domain="all"))
  current<-reactive(corpus$actions[[selected_action() %||% ""]])
  plan_field<-function(name)paste0(name,"_r",revision())
  flush_events<-function(){
    queue<-isolate(pending())
    for(ev in queue){
      ok<-tryCatch(persist_event(cfg,ev),error=function(e)FALSE)
      if(!ok){storage_error("Some records have not reached storage. Retry or download this session before closing.");return(FALSE)}
      queue<-Filter(function(x)x$event_id!=ev$event_id,queue);pending(queue)
    };storage_error(NULL);TRUE
  }
  log_event<-function(type,payload=list()){
    if(!isTRUE(isolate(recording())))return(invisible(NULL))
    ev<-list(event_id=new_id(),session_id=session_id,sequence=length(isolate(events()))+1L,timestamp_utc=utc_now(),type=type,
      participant_code=if(cfg$research_enabled)isolate(consented_participant_code()) else NULL,
      app_version=APP_VERSION,corpus_version=corpus$corpus_version,consented=TRUE,consent_version=cfg$consent_version,
      phase=if(cfg$research_enabled)"study" else "product_feedback",payload=payload)
    events(append(isolate(events()),list(ev)));pending(append(isolate(pending()),list(ev)));flush_events();invisible(ev)
  }
  choose_action<-function(id){
    if(!id %in% names(corpus$actions))return()
    selected_action(id);selected_source(corpus$actions[[id]]$evidence_source_id);revision(isolate(revision())+1L)
    updateTabsetPanel(session,"main_tab",selected="workspace")
    log_event("action_opened",list(action_id=id,content_hash=corpus$actions[[id]]$content_sha256,content_version=corpus$actions[[id]]$content_version))
  }
  action_card<-function(a){g<-corpus$guides[[a$guide_id]]
    div(class="practice-card",div(class="card-meta",span(g$domain_label),rating_badge(a)),h3(a$title),p(class="card-source",g$title),
      p(class="card-description",if(length(a$steps))a$steps[[1]]$text else "Explore the implementation sections within this recommendation."),
      event_button("choose_action",a$action_id,"Explore this practice","btn btn-primary"))
  }
  run_search<-function(){
    q<-list(query=scalar_text(input$search_question),grade=scalar_text(input$search_grade),role=scalar_text(input$search_role),domain=scalar_text(input$search_domain))
    for(k in c("grade","role","domain"))if(!nzchar(q[[k]]))q[[k]]<-"all"
    result_query(q);found<-search_actions(corpus,search_index,q$query,q$domain,q$grade,q$role,8L)
    log_event("search_submitted",c(q,list(result_ids=vapply(found,function(x)x$action$action_id,""))));found
  }
  output$home_ai_note<-renderUI(if(!cfg$ai_enabled)p(class="fine-print","AI conversation is not connected in this installation. You can explore all practices and create a plan.") else NULL)
  observeEvent(input$find_practices,run_search())
  output$search_results<-renderUI({q<-result_query();r<-search_actions(corpus,search_index,q$query,q$domain,q$grade,q$role,8L)
    if(!length(r))return(div(class="panel empty-state",h3("No matching practice found."),p("Try a different phrase, broaden the filters, or browse the collection below.")))
    div(class="practice-grid",lapply(r,function(x)action_card(x$action)))
  })
  output$guide_collection<-renderUI(div(class="guide-list",lapply(corpus$guides,function(g){
    aa<-Filter(function(a)a$guide_id==g$guide_id,corpus$actions)
    tags$details(class="guide-row",`data-event`="guide_expanded",`data-source`=g$guide_id,
      tags$summary(span(g$title),span(class="guide-count",paste(sum(vapply(aa,function(a)is.null(a$parent_id),TRUE)),"recommendations"))),
      p(g$learner_scope),p(class="fine-print",paste(substr(g$publication_date,1,4),paste(unlist(g$roles),collapse=" · "),sep=" · ")),
      lapply(aa,function(a)div(class="recommendation-row",event_button("choose_action",a$action_id,paste(a$number,a$title),"text-button"),rating_badge(a))),pdf_link(g))
  })))
  output$action_content<-renderUI({
    a<-current();if(is.null(a))return(div(class="panel empty-state",p(class="eyebrow","YOUR STARTING POINT"),
      h2("Choose a practice or start with a question."),p("Use Explore practices to select an action, or describe your situation in the conversation.")))
    g<-corpus$guides[[a$guide_id]]
    div(class="panel action-panel",p(class="eyebrow",g$domain_label),h2(a$title),rating_badge(a),p(class="card-source",g$title),
      if(!is.null(a$parent_id))p("Implementation section within recommendation ",corpus$actions[[a$parent_id]]$number),
      h3("A place to start"),p(class="lead-action",if(length(a$steps))a$steps[[1]]$text else "Open an implementation section below."),
      tags$details(class="steps-details",open="open",`data-event`="steps_expanded",`data-source`=a$action_id,
        tags$summary(paste("How to carry it out ·",length(a$steps),"components")),
        lapply(seq_along(a$steps),function(i){s<-a$steps[[i]]
          div(class="step-row",span(class="step-number",sprintf("%02d",i)),div(p(strong(s$text)),
            div(class="source-buttons",lapply(s$source_ids,function(sid)event_button("show_source",sid,paste("Source · p.",source_entry(corpus,sid,a)$pdf_page),"text-button"))),
            if(any(vapply(s[c("rationale","materials","cadence_or_dosage","monitoring","roadblocks")],function(x)length(x)>0,TRUE)))
              tags$details(tags$summary("Planning details"),if(length(s$rationale))p(s$rationale),
                if(length(s$materials))p(strong("Materials: "),paste(unlist(s$materials),collapse="; ")),
                if(length(s$cadence_or_dosage))p(strong("Timing: "),s$cadence_or_dosage),
                if(length(s$monitoring))p(strong("What to notice: "),s$monitoring),
                if(length(s$roadblocks))p(strong("Conditions and obstacles: "),paste(unlist(s$roadblocks),collapse="; ")))))
        })),
      lapply(Filter(function(c)identical(c$parent_id,a$action_id),corpus$actions),function(c)
        div(class="child-action",event_button("choose_action",c$action_id,paste("Section",c$number,c$title),"text-button"))),
      tags$details(class="scope-details",`data-event`="scope_opened",`data-source`=a$action_id,tags$summary("Fit and evidence"),
        p(g$learner_scope),p(g$scope_note),p("The evidence label applies to the original recommendation. Check the guide's evidence discussion and the conditions of your setting."),pdf_link(g,a$pdf_start)),
      div(class="toolbar",event_button("ask_action",a$action_id,"Ask about this practice","btn btn-secondary"),
        event_button("start_plan",a$action_id,"Start my plan","btn btn-primary")))
  })
  output$source_content<-renderUI({a<-current();if(is.null(a))return(NULL)
    s<-source_entry(corpus,selected_source() %||% a$evidence_source_id,a);if(is.null(s))return(NULL)
    div(class="panel evidence-panel",tags$details(open="open",tags$summary("Supporting source"),
      p(class="eyebrow",paste("SOURCE · PDF PAGE",s$pdf_page)),h3(s$title),tags$blockquote(class="source-text",s$text),
      pdf_link(corpus$guides[[s$guide_id]],s$pdf_page,"Open this page in the original PDF",s$source_id)))
  })
  output$plan_editor<-renderUI({a<-current();if(is.null(a))return(NULL)
    # Saved text is restored only on action/revision changes, not on source clicks or save events.
    prior<-isolate(saved_plans())[[a$action_id]]
    div(class="panel plan-panel",id="plan-panel",`data-revision`=revision(),p(class="eyebrow","YOUR DECISION"),h2("My next step"),
      radioButtons(plan_field("decision"),"How would you use this practice?",choices=c("Try","Adapt","Set aside"),selected=prior$decision %||% "Adapt",inline=TRUE),
      textAreaInput(plan_field("plan_notes"),"My next action",value=prior$notes %||% "",rows=5,width="100%"),
      textAreaInput(plan_field("reason"),"My reason / what I still need to check",value=prior$reason %||% "",rows=2,width="100%"),
      div(class="toolbar",actionButton("save_plan","Save my plan",class="btn-primary"),downloadButton("download_plan","Download plan",class="btn-secondary")),
      uiOutput("plan_status"),p(class="fine-print","Edit the plan in your own words. Download a copy to keep it after this session."))
  })
  output$plan_status<-renderUI({id<-selected_action();if(is.null(id)||is.null(saved_plans()[[id]]))return(NULL)
    p(class="saved-message",role="status","Saved in this workspace. Download a copy to keep it after this session.")
  })
  capture_plan<-function(notes=NULL,reason=NULL,decision=NULL,context=NULL){
    a<-isolate(current());if(is.null(a))return(NULL)
    notes<-scalar_text(notes %||% isolate(input[[plan_field("plan_notes")]]),12000)
    if(!nzchar(notes))return(NULL)
    list(action_id=a$action_id,notes=notes,reason=scalar_text(reason %||% isolate(input[[plan_field("reason")]])),
      decision=scalar_text(decision %||% isolate(input[[plan_field("decision")]]),30),
      context=scalar_text(context %||% isolate(input$teacher_context)),saved_at=utc_now(),revision=isolate(revision()))
  }
  observeEvent(input$save_request,{r<-input$save_request
    if(!is.list(r)||!identical(as.character(r$revision),as.character(revision()))||length(r$decision)!=1||!r$decision %in% c("Try","Adapt","Set aside"))return()
    p<-capture_plan(r$notes,r$reason,r$decision,r$context);if(is.null(p)){showNotification("Add your next action before saving.");return()}
    plans<-saved_plans();plans[[p$action_id]]<-p;saved_plans(plans);log_event("plan_saved",p)
  })
  observeEvent(input$export_request,{r<-input$export_request
    if(!is.list(r)||!identical(as.character(r$revision),as.character(revision()))||length(r$decision)!=1||!r$decision %in% c("Try","Adapt","Set aside"))return()
    p<-capture_plan(r$notes,r$reason,r$decision,r$context)
    if(is.null(p)){showNotification("Add your next action before exporting.");return()}
    export_plan(p);session$sendCustomMessage("download_plan_ready",list(revision=revision()))
  })
  output$download_plan<-downloadHandler(filename=function()paste0("my-teaching-plan-",Sys.Date(),".txt"),content=function(file){
    p<-isolate(export_plan()) %||% capture_plan();export_plan(NULL)
    if(is.null(p)){writeLines("Add your next action before exporting a plan.",file);return()}
    writeLines(enc2utf8(plan_export(p,corpus)),file,useBytes=TRUE);log_event("plan_exported",p)
  },contentType="text/plain; charset=utf-8")
  output$chat_context<-renderUI({a<-current();div(class="chat-context",if(is.null(a))"Across the WWC practice-guide collection" else tagList(strong("Current practice"),p(a$title)))})
  output$conversation<-renderUI({tt<-history()
    if(!length(tt))return(div(class="conversation-empty",p("A useful question starts with your setting."),p(class="muted","Ask why a practice is recommended, what an evidence label means, or how you might adjust a step.")))
    div(class="conversation",lapply(seq_along(tt),function(i){t<-tt[[i]];a<-t$response
      div(class="turn",div(class="user-message",span("YOU"),p(t$question)),div(class="assistant-message",span(class="speaker","ASKABOUTEDU · AI"),p(a$overview),
        lapply(a$blocks,function(b)div(class=paste("answer-block",b$kind),p(class="block-label",switch(b$kind,source_guidance="From the guide",adaptation="Suggested adaptation",limit="What to keep in mind",clarification="A question for you")),
          p(b$text),lapply(b$sources,function(ref){s<-named_by(t$retrieval$sources,"source_id")[[ref$source_id]]
            tags$details(class="citation",`data-event`="citation_opened",`data-source`=paste(i,ref$source_id,sep="|"),
              tags$summary(paste(s$title,"· PDF p.",s$pdf_page)),tags$blockquote(ref$quote),pdf_link(corpus$guides[[s$guide_id]],s$pdf_page,"Read original page",s$source_id))}))),
        div(class="recommended-actions",lapply(a$action_ids,function(id)event_button("choose_action",id,corpus$actions[[id]]$title,"text-button"))),
        if(nzchar(a$follow_up))p(class="followup",a$follow_up),if(nzchar(a$plan_text))tags$details(tags$summary("Proposed plan"),tags$pre(a$plan_text),
          if(!is.null(t$action_id))event_button("apply_plan",as.character(i),"Use this as my starting draft","btn btn-secondary") else p("Select a practice before adding this to a plan."))))
    }))
  })
  output$ai_status<-renderUI({
    if(busy())return(p(class="ai-status",role="status","Reading the sources and preparing an answer…"))
    if(!is.null(chat_error()))return(p(class="error-message",role="alert",chat_error()))
    if(!cfg$ai_enabled)return(p(class="fine-print","AI conversation is not connected in this installation. All practice content and the plan editor are available."))
    p(class="fine-print",paste("Answers use linked source passages.",max(0,cfg$session_limit-ai_calls()),"questions remaining in this session."))
  })
  ask<-function(question,intent="ask",setting=NULL){
    question<-scalar_text(question);if(!nzchar(question)){chat_error("Enter a question first.");return()}
    if(!cfg$ai_enabled){chat_error("AI is not connected in this installation. Explore a practice and its sources, or create a plan directly.");return()}
    if(busy())return()
    if(ai_calls()>=cfg$session_limit){chat_error("This session has reached its question limit. You can continue using the practices and plan editor.");return()}
    if(!tryCatch(reserve_ai_call(cfg),error=function(e)FALSE)){chat_error("AI is temporarily unavailable or today's allowance has been reached. You can still explore the source content.");return()}
    busy(TRUE);chat_error(NULL);ai_calls(ai_calls()+1L)
    ctx<-result_query();ctx$setting<-scalar_text(setting %||% input$teacher_context);ctx$selected_action<-selected_action()
    previous<-if(length(history()))tail(history(),1)[[1]]$question else ctx$query
    retrieval<-retrieve_context(corpus,search_index,question,selected_action(),ctx$grade,ctx$role,previous)
    generation<-chat_generation();aid<-selected_action();started<-utc_now()
    recording_epoch<-if(recording())consent_epoch() else NULL
    log_reply<-function(type,payload){
      if(!is.null(recording_epoch)&&identical(recording_epoch,isolate(consent_epoch())))log_event(type,payload)
    }
    request<-build_ai_request(question,history(),ctx,retrieval,cfg,intent)
    log_event("ai_question",list(question=question,context=ctx,intent=intent,retrieval=retrieval,prompt_version=PROMPT_VERSION,model=cfg$model))
    updateTextAreaInput(session,"chat_question",value="")
    worker_cfg<-cfg[c("api_key","model")]
    task<-promises::future_promise(perform_ai_request(request,worker_cfg),globals=list(request=request,worker_cfg=worker_cfg,
      perform_ai_request=perform_ai_request,post_json=post_json,json=json,`%||%`=`%||%`),packages=c("curl","jsonlite"),seed=TRUE)
    promises::then(task,onFulfilled=function(result){
      if(session$isClosed())return(NULL)
      busy(FALSE);if(!identical(generation,isolate(chat_generation())))return(NULL)
      answer<-tryCatch(validate_ai_response(result$answer,retrieval),error=function(e)NULL)
      if(is.null(answer)){chat_error("The answer did not pass its source checks. Please try a narrower question or inspect the original practice.")
        log_reply("ai_answer_rejected",list(question=question,response_id=result$response_id,model=result$model,candidate_response=result$answer,usage=result$usage,prompt_version=PROMPT_VERSION));return(NULL)}
      turn<-list(question=question,response=answer,action_id=aid,context=ctx,retrieval=retrieval,model=result$model,response_id=result$response_id,
        usage=result$usage,prompt_version=PROMPT_VERSION,started_at=started,completed_at=utc_now())
      history(append(isolate(history()),list(turn)));log_reply("ai_answer_displayed",turn);session$sendCustomMessage("chat_updated",list())
    },onRejected=function(error){
      if(session$isClosed())return(NULL)
      busy(FALSE);if(!identical(generation,isolate(chat_generation())))return(NULL)
      chat_error("The AI service could not complete this request. Your plan is unchanged; please try again.")
      log_reply("ai_service_error",list(question=question,started_at=started,model=cfg$model))
    });invisible(NULL)
  }
  observeEvent(input$ask_home,{run_search();selected_action(NULL);selected_source(NULL);revision(revision()+1L)
    updateTabsetPanel(session,"main_tab",selected="workspace")
    setting<-paste("Grade / stage:",result_query()$grade,"; Role:",result_query()$role)
    updateTextAreaInput(session,"teacher_context",value=setting);ask(input$search_question,setting=setting)
  })
  observeEvent(input$send_request,{r<-input$send_request;if(!is.list(r))return();ask(r$question,setting=r$context)})
  observeEvent(input$adapt_request,{r<-input$adapt_request
    if(is.null(current())){chat_error("Choose a practice first so the plan can stay linked to its source.");return()}
    ask(paste("Help me adapt this practice into a concrete next step for my setting.",scalar_text(r$context)),"adapt",r$context)
  })
  observeEvent(input$clear_chat,{chat_generation(chat_generation()+1L);history(list());chat_error(NULL);log_event("conversation_cleared");updateTextAreaInput(session,"chat_question",value="")})
  observeEvent(input$ui_event,{
    e<-input$ui_event;if(!is.list(e))return();type<-scalar_text(e$type,60);id<-scalar_text(e$source,200)
    if(type=="choose_action"){choose_action(id);return()}
    if(type=="show_source"){a<-current();s<-source_entry(corpus,id,a)
      if(!is.null(a)&&!is.null(s)&&s$guide_id==a$guide_id){selected_source(id);log_event("source_opened",list(action_id=a$action_id,source_id=id));session$sendCustomMessage("show_source",list())};return()}
    if(type=="ask_action"&&id %in% names(corpus$actions)){updateTextAreaInput(session,"chat_question",value=paste("Explain how to carry out this practice and what its evidence label means:",corpus$actions[[id]]$title));session$sendCustomMessage("focus_chat",list());return()}
    if(type=="start_plan"&&identical(id,selected_action())){session$sendCustomMessage("show_plan",list());return()}
    if(type=="apply_plan"){i<-suppressWarnings(as.integer(id));if(is.na(i)||i<1||i>length(history()))return();t<-history()[[i]]
      if(is.null(t$action_id)||!identical(t$action_id,selected_action())){showNotification("Open the practice associated with that response before applying its plan.");return()}
      updateTextAreaInput(session,plan_field("plan_notes"),value=t$response$plan_text);updateRadioButtons(session,plan_field("decision"),selected="Adapt")
      log_event("ai_plan_loaded_for_edit",list(action_id=t$action_id,plan_text=t$response$plan_text,response_id=t$response_id));session$sendCustomMessage("show_plan",list());return()}
    if(type %in% c("pdf_opened","guide_expanded","steps_expanded","scope_opened","citation_opened"))log_event(type,list(source_id=id,action_id=selected_action()))
  })
  observeEvent(input$record_consent,{
    consent_epoch(consent_epoch()+1L)
    if(isTRUE(input$record_consent)){
      if(cfg$research_enabled&&!nzchar(scalar_text(input$participant_code))){updateCheckboxInput(session,"record_consent",value=FALSE);showNotification("Enter the study code before starting research recording.");return()}
      consented_participant_code(if(cfg$research_enabled)scalar_text(input$participant_code,80) else NULL)
      recording(TRUE);log_event("consent_given",list(text=cfg$consent_text,version=cfg$consent_version))
    }else{if(isTRUE(recording()))log_event("recording_stopped");recording(FALSE)}
  },ignoreInit=TRUE)
  observeEvent(input$retry_storage,flush_events())
  output$storage_status<-renderUI(div(role="status",p(if(recording())"Recording is on." else "Recording is off. No new interaction records are being saved."),
    p(class="fine-print",paste(length(events())-length(pending()),"records saved;",length(pending()),"pending.")),if(!is.null(storage_error()))p(class="error-message",storage_error())))
  observeEvent(input$delete_session,{
    ok<-tryCatch(delete_session_data(cfg,session_id),error=function(e)FALSE)
    if(ok){pending(list());events(list());recording(FALSE);storage_error(NULL);updateCheckboxInput(session,"record_consent",value=FALSE);showNotification("Saved data for this session was deleted. Recording is off.")}
    else storage_error("Deletion could not be confirmed. Please retry before closing this session.")
  })
  output$download_session<-downloadHandler(filename=function()paste0("wwc-session-",Sys.Date(),".json"),content=function(file){
    jsonlite::write_json(list(session_id=session_id,app_version=APP_VERSION,corpus_version=corpus$corpus_version,downloaded_at=utc_now(),
      conversation=isolate(history()),plans=isolate(saved_plans()),consented_events=isolate(events()),
      pending_event_ids=vapply(isolate(pending()),function(e)e$event_id,"")),file,pretty=TRUE,auto_unbox=TRUE,null="null")
  },contentType="application/json")
}
