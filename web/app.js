/* walkthrough app shell — bootstraps the renderer, fetches the initial
 * model snapshot, subscribes to live focus updates, and wires clicks to
 * reveal-in-Neovim + focus-overlay actions. Adapted from cartograph.nvim's
 * app.js's send()/connect() plumbing, trimmed to what Phase 1 needs (no
 * search/filters/compare/3D toggle -- one renderer, one model, small by
 * design).
 */
(function () {
  'use strict';

  var params = new URLSearchParams(window.location.search);
  var token = params.get('token') || '';

  function withToken(path) {
    if (!token) return path;
    return path + (path.indexOf('?') === -1 ? '?' : '&') + 'token=' + encodeURIComponent(token);
  }

  function setStatus(text, connected) {
    var el = document.getElementById('status');
    el.querySelector('.status-label').textContent = text;
    el.classList.toggle('is-connected', !!connected);
  }

  function send(action, data) {
    var body = Object.assign({ action: action }, data || {});
    return fetch(withToken('/api/message'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }).then(function (r) {
      return r.json();
    });
  }

  /* Find an entity (component/relationship/decision/assumption) by id
   * across every collection that shares the id namespace. */
  function findEntity(model, id) {
    var collections = ['components', 'relationships', 'decisions', 'assumptions'];
    for (var i = 0; i < collections.length; i++) {
      var list = model[collections[i]] || [];
      for (var j = 0; j < list.length; j++) {
        if (list[j].id === id) return list[j];
      }
    }
    return null;
  }

  function sep() {
    var s = document.createElement('span');
    s.className = 'sep';
    s.textContent = '·';
    return s;
  }

  var model = null;
  var view = null;
  var detail = document.getElementById('detail');
  var focusedId = null; // the entity the detail panel is currently showing, if any

  function showEntity(id) {
    focusedId = id;
    WalkthroughDetailPanel.show(detail, findEntity(model, id), {
      onAccept: function () {
        send('accept', { nodeId: id });
      },
      onChallenge: function () {
        send('challenge', { nodeId: id });
      },
      onCorrect: function (note) {
        send('correct', { nodeId: id, note: note });
      },
    });
  }

  /* Shared by the architecture graph's node click and every secondary
   * view's entity click -- same three effects everywhere a component is
   * clicked: jump Neovim to it, highlight it in the (possibly hidden)
   * architecture graph, and show its detail panel. */
  function focusAndReveal(id) {
    send('reveal', { nodeId: id });
    send('focus', { nodeId: id });
    showEntity(id);
  }

  function revealEvidence(file, line) {
    send('revealAt', { file: file, line: line || 1 });
  }

  function connect() {
    var es = new EventSource(withToken('/events'));
    es.addEventListener('focus:update', function (e) {
      try {
        view.applyFocus(JSON.parse(e.data));
      } catch (_) {
        /* ignore malformed/late event */
      }
    });
    es.addEventListener('model:update', function (e) {
      try {
        var d = JSON.parse(e.data);
        model = d.model;
        view.updateEntities(model);
        secondaryViews.sequence.render(model);
        secondaryViews.lineage.render(model);
        secondaryViews.decisions.render(model);
        if (focusedId) showEntity(focusedId); // refresh the open panel with the new status
      } catch (_) {
        /* ignore malformed/late event */
      }
    });
    es.addEventListener('status', function (e) {
      try {
        var d = JSON.parse(e.data);
        setStatus(d.connected ? 'connected' : d.message || '', d.connected);
      } catch (_) {
        setStatus('connected', true);
      }
    });
    es.onerror = function () {
      setStatus('disconnected', false);
    };
  }

  var VIEWS = ['architecture', 'sequence', 'lineage', 'decisions'];
  var secondaryViews = {};
  var activeView = 'architecture';

  function switchView(name) {
    activeView = name;
    VIEWS.forEach(function (v) {
      var isActive = v === name;
      var container = v === 'architecture' ? document.getElementById('cy') : document.getElementById('view-' + v);
      container.hidden = !isActive;
      var tab = document.querySelector('.view-tab[data-view="' + v + '"]');
      if (tab) tab.classList.toggle('is-active', isActive);
    });
    document.getElementById('fit').hidden = name !== 'architecture';
    if (name === 'architecture') view.fit();
  }

  function init() {
    var entityCtx = { onEntityClick: focusAndReveal, onEvidenceClick: revealEvidence };
    secondaryViews.sequence = window.createSequenceView(document.getElementById('view-sequence'), entityCtx);
    secondaryViews.lineage = window.createLineageView(document.getElementById('view-lineage'), entityCtx);
    secondaryViews.decisions = window.createDecisionView(document.getElementById('view-decisions'), entityCtx);

    document.querySelectorAll('.view-tab').forEach(function (tab) {
      tab.addEventListener('click', function () {
        switchView(tab.getAttribute('data-view'));
      });
    });

    view = window.createComponentRenderer({
      container: document.getElementById('cy'),
      onNodeClick: focusAndReveal,
      onClearFocus: function () {
        send('clearFocus');
        focusedId = null;
        WalkthroughDetailPanel.show(detail, null);
      },
    });

    document.getElementById('fit').addEventListener('click', function () {
      view.fit();
    });

    setStatus('loading…');
    fetch(withToken('/api/model'))
      .then(function (r) {
        if (!r.ok) throw new Error('no active model');
        return r.json();
      })
      .then(function (snapshot) {
        model = snapshot.model;
        var titleEl = document.getElementById('wt-title');
        titleEl.innerHTML = '';
        titleEl.appendChild(document.createTextNode(model.walkthrough_id));
        titleEl.appendChild(sep());
        titleEl.appendChild(document.createTextNode(model.revision_id));
        titleEl.appendChild(sep());
        var statusSpan = document.createElement('span');
        statusSpan.className = 'wt-status';
        statusSpan.textContent = model.status;
        titleEl.appendChild(statusSpan);
        view.ingest(model);
        view.applyFocus(snapshot.focus);
        secondaryViews.sequence.render(model);
        secondaryViews.lineage.render(model);
        secondaryViews.decisions.render(model);
        switchView(activeView);
        setTimeout(function () {
          view.fit();
        }, 250);
        connect();
      })
      .catch(function (e) {
        setStatus('error: ' + e.message);
      });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
