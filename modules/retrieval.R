query_terms <- function(text) {
  text <- tolower(paste(text, collapse = " "))
  translations <- c("阅读"=" reading comprehension", "解码"=" decoding", "词汇"=" vocabulary", "多音节"=" multisyllabic decoding",
    "数学"=" mathematics", "分数"=" fractions", "代数"=" algebra", "写作"=" writing", "行为"=" behavior",
    "幼儿"=" preschool", "大学"=" postsecondary college", "升学"=" college access", "辍学"=" dropout",
    "科学"=" science", "英语学习者"=" english learners", "学术语言"=" academic vocabulary language",
    "小组"=" small group intervention", "注意力"=" attention engagement", "流利"=" fluency", "数据"=" data")
  for (term in names(translations)) if (grepl(term, text, fixed = TRUE)) text <- paste(text, translations[[term]])
  text <- gsub("[^a-z0-9]+", " ", text)
  words <- strsplit(text, "\\s+")[[1]]
  stops <- c("the","a","an","and","or","for","to","of","in","on","at","with","from","by","as","is","are","be","it","this","that","these","those","i","my","our","we","you","your","their","can","could","would","should","do","does","did","have","has","had","what","how","why","when","which","about","some","all","also","me","help","need","want","please","student","students","teacher","teachers","teach","teaching","use","using","guide","practice","recommendation","more","only","not","will","into","them","they","if","than","but","make","get","ways")
  words <- words[nchar(words)>2 & !words %in% stops]
  # Small deterministic stemmer and synonym groups; no model is used for search.
  words <- sub("(ments|ment|ing|ies|es|s)$", "", words)
  map <- c("read"="read","decod"="decod","behavioral"="behavior","behaviour"="behavior","math"="math","mathematic"="math",
    "struggl"="difficult","difficulti"="difficult","difficult"="difficult","writ"="writ","written"="writ",
    "vocabulari"="vocabulary","vocabulary"="vocabulary","word"="word","multisyllabic"="multisyllabic")
  hit <- words %in% names(map); words[hit] <- map[words[hit]]
  words[nchar(words)>1]
}

build_search <- function(corpus) {
  docs <- lapply(corpus$actions, function(a) {
    g <- corpus$guides[[a$guide_id]]
    text <- c(rep(a$title, 4), vapply(a$steps, function(s) s$text, ""),
      g$title, g$learner_scope, paste(unlist(g$keywords), collapse = " "), a$summary_zh)
    table(query_terms(text))
  })
  vocabulary <- unique(unlist(lapply(docs, names), use.names = FALSE))
  df <- setNames(vapply(vocabulary, function(t) sum(vapply(docs, function(d) t %in% names(d), TRUE)), 0L), vocabulary)
  list(docs = docs, idf = log(1 + (length(docs) - df + 0.5)/(df + 0.5)),
    lengths = vapply(docs, sum, 0), average = mean(vapply(docs, sum, 0)))
}

search_actions <- function(corpus, index, query = "", domain = "all", grade = "all", role = "all", limit = 12L) {
  ids <- names(Filter(function(a) {
    g <- corpus$guides[[a$guide_id]]
    (domain == "all" || g$domain_id == domain) &&
      (grade == "all" || !length(g$grades) || grade %in% unlist(g$grades)) &&
      (role == "all" || role %in% unlist(g$roles))
  }, corpus$actions))
  if (!length(ids)) return(list())
  terms <- unique(query_terms(query)); terms <- intersect(terms, names(index$idf))
  if (nzchar(trimws(query)) && !length(terms)) return(list())
  scores <- setNames(rep(0, length(ids)), ids)
  if (length(terms)) for (id in ids) {
    tf <- index$docs[[id]][terms]; tf[is.na(tf)] <- 0
    scores[id] <- sum(index$idf[terms] * tf * 2.2/(tf + 1.2*(0.25 + 0.75*index$lengths[[id]]/index$average)))
  }
  if (length(terms)) ids <- ids[scores > 0]
  ids <- ids[order(-scores[ids], vapply(corpus$actions[ids], function(a) a$title, ""))]
  lapply(head(ids, limit), function(id) list(action = corpus$actions[[id]], score = unname(scores[id])))
}

source_entry <- function(corpus, id, action = NULL) {
  p <- corpus$passages[[id]]
  if (!is.null(p)) return(c(p, list(title = corpus$guides[[p$guide_id]]$title,
    filename = corpus$guides[[p$guide_id]]$source_filename)))
  actions <- if (is.null(action)) corpus$actions else list(action)
  for (a in actions) for (loc in a$locators) if (loc$source_id == id)
    return(c(loc, list(guide_id = a$guide_id, title = corpus$guides[[a$guide_id]]$title,
      filename = corpus$guides[[a$guide_id]]$source_filename)))
  NULL
}

retrieve_context <- function(corpus, index, query, pinned = NULL, grade = "all", role = "all", prior_query = "") {
  found <- search_actions(corpus, index, paste(query, prior_query), grade = grade, role = role, limit = 5L)
  ids <- vapply(found, function(x) x$action$action_id, "")
  if (!is.null(pinned) && pinned %in% names(corpus$actions)) ids <- unique(c(pinned, head(ids, 3)))
  # Retain child implementation divisions when a parent recommendation is selected.
  children <- names(Filter(function(a) !is.null(a$parent_id) && a$parent_id %in% ids, corpus$actions))
  ids <- head(unique(c(ids, children)), 8)
  packets <- list(); action_info <- list(); terms <- unique(query_terms(paste(query, prior_query)))
  for (id in ids) {
    a <- corpus$actions[[id]]; g <- corpus$guides[[a$guide_id]]
    action_info[[length(action_info)+1L]] <- list(action_id = id, title = a$title,
      guide = g$title, evidence = a$evidence, parent_id = a$parent_id,
      scope = g$learner_scope, scope_note = g$scope_note, grades = g$grades, roles = g$roles,
      implementation_paraphrases = head(lapply(a$steps, function(s) list(text = s$text, sources = s$source_ids)), 8))
    pages <- corpus$passages[unlist(a$page_ids)]
    score <- vapply(pages, function(p) sum(query_terms(p$text) %in% terms), 0L)
    page_ids <- unique(c(a$evidence_source_id, head(names(sort(score, decreasing = TRUE)), if (identical(id, pinned)) 3L else 1L)))
    for (sid in page_ids) {
      p <- source_entry(corpus, sid)
      # Each excerpt is contiguous, with a recorded offset into the full page.
      text <- p$text
      if (nchar(text)>7000L) {
        pos <- vapply(terms, function(t) regexpr(t, tolower(text), fixed = TRUE)[1], 0L)
        pos <- pos[pos>0L]; start <- if (length(pos)) max(1L, min(pos)-1000L) else 1L
        start <- min(start, nchar(text)-6999L)
        p$text <- substr(text, start, start+6999L);p$character_start <- start
      } else p$character_start <- 1L
      packets[[sid]] <- p
    }
    # Source excerpts supporting the displayed actions must also be available to the model.
    for (s in head(a$steps, if (identical(id, pinned)) 8L else 2L)) for (sid in s$source_ids)
      packets[[sid]] <- source_entry(corpus, sid, a)
  }
  list(actions = action_info, sources = unname(packets), action_ids = ids,
    retrieval_version = "bm25-actions-pages-v1")
}

plan_export <- function(plan, corpus) {
  a <- corpus$actions[[plan$action_id]]; g <- corpus$guides[[a$guide_id]]
  paste(c("AskAboutEdu | My teaching plan", "", paste("Practice:", a$title),
    paste("Source:", g$title), paste("WWC evidence label:", a$evidence),
    paste("Source pages:", a$pdf_start, "to", a$pdf_end),
    paste("Original PDF:", paste0("https://ies.ed.gov/ncee/wwc/Docs/PracticeGuide/", g$source_filename)),
    "", "My setting", plan$context, "", "My next action", plan$notes,
    "", paste("My decision:", plan$decision), "My reason / what to check", plan$reason,
    "", "The plan is my adaptation. The WWC evidence label applies to the original recommendation.",
    paste("Action ID:", a$action_id), paste("Content hash:", a$content_sha256),
    paste("App version:", APP_VERSION), paste("Corpus version:", corpus$corpus_version),
    paste("Saved UTC:", plan$saved_at)), collapse = "\n")
}
