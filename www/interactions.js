(function () {
  'use strict';
  let sequence = 0;
  let downloadReady = false;
  function send(name, data) {
    if (!window.Shiny) return;
    Shiny.setInputValue(name, Object.assign({}, data, {nonce: Date.now() + '-' + (++sequence)}), {priority:'event'});
  }
  function flush(panel) {
    if (!panel || !window.Shiny) return;
    panel.querySelectorAll('textarea[id], select[id], input[type=radio]:checked').forEach(function (el) {
      Shiny.setInputValue(el.type === 'radio' ? el.name : el.id, el.value, {priority:'event'});
    });
  }
  document.addEventListener('click', function (e) {
    if (!(e.target instanceof Element)) return;
    const b = e.target.closest('button, a');
    if (!b) return;
    if (b.id === 'find_practices' || b.id === 'ask_home') flush(b.closest('.search-panel'));
    if (b.id === 'send_chat' || b.id === 'adapt_action') {
      const panel = b.closest('.chat-composer'); flush(panel);
      send(b.id === 'send_chat' ? 'send_request' : 'adapt_request', {
        question: document.getElementById('chat_question').value,
        context: document.getElementById('teacher_context').value
      });
    }
    if (b.id === 'save_plan' || (b.id === 'download_plan' && !downloadReady)) {
      if (b.id === 'download_plan') { e.preventDefault(); e.stopImmediatePropagation(); }
      const panel = b.closest('.plan-panel'); flush(panel);
      const decision = panel.querySelector('input[type=radio]:checked');
      send(b.id === 'save_plan' ? 'save_request' : 'export_request', {revision:panel.dataset.revision, decision:decision ? decision.value : '',
        notes:panel.querySelector('textarea[id^=plan_notes_]').value,
        reason:panel.querySelector('textarea[id^=reason_]').value,
        context:document.getElementById('teacher_context').value});
      if (b.id === 'download_plan') return;
    }
    if (b.id === 'download_plan') downloadReady = false;
    const item = e.target.closest('[data-event]');
    if (item && item.tagName !== 'DETAILS') send('ui_event', {type:item.dataset.event,source:item.dataset.source || ''});
  }, true);
  document.addEventListener('toggle', function (e) {
    const el = e.target;
    if (el instanceof Element && el.tagName === 'DETAILS' && el.open && el.dataset.event)
      send('ui_event', {type:el.dataset.event,source:el.dataset.source || ''});
  }, true);
  function jump(selector) { const el=document.querySelector(selector); if(el) el.scrollIntoView({behavior:'smooth',block:'start'}); }
  function registerHandlers() {
    Shiny.addCustomMessageHandler('show_source',function(message){jump('.evidence-panel');});
    Shiny.addCustomMessageHandler('show_plan',function(message){jump('#plan-panel');});
    Shiny.addCustomMessageHandler('focus_chat',function(message){jump('.chat-composer');document.getElementById('chat_question').focus();});
    Shiny.addCustomMessageHandler('chat_updated',function(message){setTimeout(function(){const c=document.querySelector('.conversation');if(c)c.scrollTop=c.scrollHeight;},120);});
    Shiny.addCustomMessageHandler('download_plan_ready',function(data){
      const panel=document.getElementById('plan-panel');
      const link=document.getElementById('download_plan');
      if(panel && link && panel.dataset.revision === String(data.revision)) { downloadReady=true; link.click(); }
    });
  }
  // Shiny emits connection events through jQuery, not native DOM dispatch.
  if (window.jQuery) window.jQuery(document).on('shiny:connected',registerHandlers);
  else document.addEventListener('shiny:connected',registerHandlers);
}());
