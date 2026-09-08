# Offline diagnostics and request configuration. Never read .Renviron or call a provider.
source("modules/core.R", encoding="UTF-8")
source("modules/ai.R", encoding="UTF-8")
Sys.setenv(WWC_APP_MODE="local", WWC_STORAGE_BACKEND="sqlite", WWC_RESEARCH_ENABLED="false",
  OPENAI_API_KEY="", WWC_AI_MODEL="gpt-5.6-sol")
Sys.unsetenv(c("WWC_AI_MAX_OUTPUT_TOKENS", "WWC_AI_REASONING_EFFORT", "WWC_AI_TIMEOUT_SECONDS"))
cfg<-app_config()
stopifnot(cfg$max_output_tokens==4000L,cfg$ai_timeout==60L)
request<-build_ai_request("Explain",list(),list(),list(),cfg)
stopifnot(is.null(request$reasoning),!request$store,request$text$format$strict)
Sys.setenv(WWC_AI_REASONING_EFFORT="low",WWC_AI_MAX_OUTPUT_TOKENS="1800",WWC_AI_TIMEOUT_SECONDS="90")
cfg<-app_config();request<-build_ai_request("Explain",list(),list(),list(),cfg)
stopifnot(request$reasoning$effort=="low",request$max_output_tokens==1800L,cfg$ai_timeout==90L)
capture<-function(expr)tryCatch({force(expr);NULL},error=function(e)e)
Sys.setenv(WWC_AI_REASONING_EFFORT="typo");stopifnot(inherits(capture(app_config()),"error"))
Sys.setenv(WWC_AI_REASONING_EFFORT="low",WWC_AI_MAX_OUTPUT_TOKENS="4001")
stopifnot(inherits(capture(app_config()),"error"))
sentinel<-"PRIVATE_INPUT_MUST_NEVER_BE_LOGGED"
http_error<-function(status,code){
  r<-list(status_code=status,content=charToRaw(json(list(error=list(code=code,message=sentinel)))))
  capture(parse_service_response(r))
}
cases<-list(list(401L,"invalid_api_key","AI-AUTHENTICATION"),list(404L,"model_not_found","AI-MODEL-ACCESS"),
  list(429L,"insufficient_quota","AI-BILLING"),list(429L,"rate_limit_exceeded","AI-RATE-LIMIT"),
  list(400L,"unsupported_parameter","AI-REQUEST-CONFIG"),list(503L,NULL,"AI-UPSTREAM"),
  list(400L,sentinel,"AI-REQUEST-CONFIG"))
for(c in cases){e<-http_error(c[[1]],c[[2]]);d<-ai_failure_details(e)
  stopifnot(d$reference==c[[3]],!grepl(sentinel,json(d),fixed=TRUE),!grepl(sentinel,conditionMessage(e),fixed=TRUE))}
stopifnot(is.null(ai_failure_details(http_error(400L,sentinel))$provider_code))
stopifnot(ai_failure_details(simpleError(sentinel))$reference=="AI-INTERNAL",
  !grepl(sentinel,json(ai_failure_details(simpleError(sentinel))),fixed=TRUE))
stopifnot(ai_failure_details(capture(parse_service_response(list(status_code=200L,content=charToRaw("not json")))))$reference=="AI-INVALID-RESPONSE")
seen_timeout<-NULL
post_json<-function(url,body,headers=list(),timeout=45){seen_timeout<<-timeout
  list(status="incomplete",incomplete_details=list(reason="max_output_tokens"),output=list())}
e<-capture(perform_ai_request(request,cfg))
stopifnot(seen_timeout==90L,ai_failure_details(e)$reference=="AI-OUTPUT-LIMIT")
cat("PASS: configurable reasoning/budget/timeout; distinct HTTP, billing and output-limit failures; raw provider messages excluded. No live request used.\n")
