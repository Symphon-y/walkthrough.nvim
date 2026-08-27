/* walkthrough secondary views — sequence, data-lineage, decision map.
 *
 * These are linear/tree shapes, not general graphs, so they're plain DOM
 * card layouts rather than a force/dagre-laid-out canvas -- simpler,
 * scales naturally with content, and reuses the same badge CSS classes
 * as the detail panel (see the dataviz-skill-sourced palette in
 * web/styles.css) instead of inventing a second visual language.
 *
 * ctx: { onEntityClick(id), onEvidenceClick(file, line) }
 * Each create*View(container, ctx) returns { render(model) }.
 */

(function () {
  'use strict';

  var STATUS_LABEL = {
    proposed: 'Proposed',
    accepted: 'Accepted',
    challenged: 'Challenged',
    corrected: 'Corrected',
    unresolved: 'Unresolved',
  };

  function el(tag, className, text) {
    var e = document.createElement(tag);
    if (className) e.className = className;
    if (text != null) e.textContent = text;
    return e;
  }

  function claimBadgeClass(claim_type) {
    if (claim_type === 'OBSERVED') return 'claim-observed';
    if (claim_type === 'INFERRED') return 'claim-inferred';
    if (claim_type === 'PROPOSED') return 'claim-proposed';
    return 'claim-unknown';
  }

  function claimBadges(entity) {
    var wrap = el('span', 'v-badges');
    wrap.appendChild(el('span', 'badge ' + claimBadgeClass(entity.claim_type), entity.claim_type || 'UNKNOWN'));
    if (entity.confidence) wrap.appendChild(el('span', 'badge confidence', entity.confidence));
    if (entity.status) {
      wrap.appendChild(el('span', 'badge status-' + entity.status, STATUS_LABEL[entity.status] || entity.status));
    }
    return wrap;
  }

  function evidenceList(evidence, ctx) {
    var wrap = el('div', 'v-evidence-list');
    (evidence || []).forEach(function (e) {
      var line = e.file + (e.line ? ':' + e.line : '') + (e.symbol ? '  (' + e.symbol + ')' : '');
      var item = el('button', 'v-evidence-link', line);
      item.addEventListener('click', function () {
        ctx.onEvidenceClick(e.file, e.line || 1);
      });
      wrap.appendChild(item);
    });
    return wrap;
  }

  function emptyState(container, message) {
    container.appendChild(el('div', 'v-empty', message));
  }

  // ---- sequence -------------------------------------------------------

  window.createSequenceView = function (container, ctx) {
    function render(model) {
      container.innerHTML = '';
      var flows = model.flows || [];
      if (flows.length === 0) {
        emptyState(container, 'No flows in this walkthrough.');
        return;
      }
      flows.forEach(function (flow) {
        var card = el('section', 'v-card');
        card.appendChild(el('h2', 'v-card-title', flow.name));

        var steps = (flow.steps || []).slice().sort(function (a, b) { return (a.seq || 0) - (b.seq || 0); });
        var list = el('ol', 'v-steps');
        steps.forEach(function (step) {
          var li = el('li', 'v-step');
          var marker = el('span', 'v-step-marker', String(step.seq != null ? step.seq : ''));
          li.appendChild(marker);

          var body = el('div', 'v-step-body');
          var head = el('div', 'v-step-head');
          if (step.component) {
            var compBtn = el('button', 'v-step-component', step.component.replace(/^component:/, ''));
            compBtn.addEventListener('click', function () {
              ctx.onEntityClick(step.component);
            });
            head.appendChild(compBtn);
          }
          head.appendChild(claimBadges(step));
          body.appendChild(head);
          body.appendChild(el('div', 'v-step-action', step.action));
          if (step.evidence && step.evidence.length) body.appendChild(evidenceList(step.evidence, ctx));
          li.appendChild(body);
          list.appendChild(li);
        });
        card.appendChild(list);
        container.appendChild(card);
      });
    }
    return { render: render };
  };

  // ---- data lineage -----------------------------------------------------

  window.createLineageView = function (container, ctx) {
    function render(model) {
      container.innerHTML = '';
      var lineages = model.data_lineage || [];
      if (lineages.length === 0) {
        emptyState(container, 'No data lineage in this walkthrough.');
        return;
      }
      lineages.forEach(function (lineage) {
        var card = el('section', 'v-card');
        card.appendChild(el('h2', 'v-card-title', lineage.name));

        var chain = el('div', 'v-chain');
        var stages = (lineage.stages || []).slice().sort(function (a, b) { return (a.seq || 0) - (b.seq || 0); });
        stages.forEach(function (stage, i) {
          if (i > 0) chain.appendChild(el('span', 'v-chain-arrow', '→'));

          var stageEl = el('div', 'v-stage');
          stageEl.appendChild(el('div', 'v-stage-shape', stage.shape));
          if (stage.component) {
            var compBtn = el('button', 'v-stage-component', stage.component.replace(/^component:/, ''));
            compBtn.addEventListener('click', function () {
              ctx.onEntityClick(stage.component);
            });
            stageEl.appendChild(compBtn);
          }
          stageEl.appendChild(claimBadges(stage));
          if (stage.transformed_by) {
            var tb = stage.transformed_by;
            var line = (tb.symbol || tb.file) + (tb.line ? ':' + tb.line : '');
            var link = el('button', 'v-evidence-link', line);
            link.addEventListener('click', function () {
              ctx.onEvidenceClick(tb.file, tb.line || 1);
            });
            stageEl.appendChild(link);
          }
          chain.appendChild(stageEl);
        });
        card.appendChild(chain);
        container.appendChild(card);
      });
    }
    return { render: render };
  };

  // ---- decisions --------------------------------------------------------

  window.createDecisionView = function (container, ctx) {
    function render(model) {
      container.innerHTML = '';
      var decisions = model.decisions || [];
      if (decisions.length === 0) {
        emptyState(container, 'No decisions in this walkthrough.');
        return;
      }
      decisions.forEach(function (d) {
        var card = el('section', 'v-card');
        var head = el('div', 'v-step-head');
        head.appendChild(el('h2', 'v-card-title', d.question));
        head.appendChild(claimBadges(d));
        card.appendChild(head);

        (d.options || []).forEach(function (opt) {
          var row = el('div', 'v-option v-option-' + opt.outcome);
          var rowHead = el('div', 'v-option-head');
          rowHead.appendChild(el('span', 'badge ' + (opt.outcome === 'chosen' ? 'status-accepted' : 'status-proposed'), opt.outcome));
          rowHead.appendChild(el('span', 'v-option-text', opt.option));
          row.appendChild(rowHead);
          if (opt.reason) row.appendChild(el('div', 'v-option-reason', opt.reason));
          if (opt.evidence && opt.evidence.length) row.appendChild(evidenceList(opt.evidence, ctx));
          card.appendChild(row);
        });

        container.appendChild(card);
      });
    }
    return { render: render };
  };
})();
