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

  function connect() {
    var es = new EventSource(withToken('/events'));
    es.addEventListener('focus:update', function (e) {
      try {
        view.applyFocus(JSON.parse(e.data));
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

  function init() {
    view = window.createComponentRenderer({
      container: document.getElementById('cy'),
      onNodeClick: function (id) {
        send('reveal', { nodeId: id });
        send('focus', { nodeId: id });
        WalkthroughDetailPanel.show(detail, findEntity(model, id));
      },
      onClearFocus: function () {
        send('clearFocus');
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
