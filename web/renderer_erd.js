/* walkthrough data-model (ER) renderer — Cytoscape + dagre.
 *
 * A DB entity's relationships are topologically a graph, same as the
 * architecture diagram, but a visually *distinct* one -- table-box nodes
 * (name + a few notable fields), ER relationships (has_one/has_many/
 * belongs_to/many_to_many) as the prominent edges, and any component that
 * reads/writes a shown entity rendered small and secondary, so this one
 * view answers both "how does the data relate" and "who touches it."
 * Own small color/fill helpers rather than importing renderer_component.js's
 * -- matches this codebase's existing per-renderer-file convention
 * (renderer_views.js and renderer_delta.js each carry their own small
 * el()/badge helpers the same way).
 *
 * ctx: { container, emptyEl, onNodeClick(id), onClearFocus() }
 * (emptyEl: an element toggled visible when there are no data_entities --
 * Cytoscape owns `container` entirely, so the "nothing to show" message
 * has to live in a sibling element, not be written into container itself.)
 * returns: { render(model), fit() }
 *
 * fit() must be called again whenever this view's tab actually becomes
 * visible (see app.js's switchView), not just once at render time --
 * render() typically runs while the tab is still hidden (architecture is
 * the default active tab), and Cytoscape's layout/fit produce a
 * degenerate result against a hidden (zero-size) container.
 */
window.createErdRenderer = function (ctx) {
  'use strict';

  var ER_KINDS = { has_one: true, has_many: true, belongs_to: true, many_to_many: true };
  var TOUCH_KINDS = { reads: true, writes: true };

  function cssVar(name) {
    return getComputedStyle(document.body).getPropertyValue(name).trim();
  }

  function claimColor(claim_type) {
    if (claim_type === 'OBSERVED') return cssVar('--claim-solid');
    if (claim_type === 'PROPOSED') return cssVar('--proposed-accent');
    return 'transparent'; // INFERRED gets its own wash below; UNKNOWN outline only
  }

  function claimOpacity(claim_type) {
    if (claim_type === 'OBSERVED') return 1;
    if (claim_type === 'INFERRED') return 0.16;
    return 0; // UNKNOWN / PROPOSED: outline only
  }

  function statusColor(status, claim_type) {
    if (status === 'accepted') return cssVar('--status-good');
    if (status === 'challenged') return cssVar('--status-critical');
    if (status === 'corrected') return cssVar('--status-warning');
    if (claim_type === 'PROPOSED') return cssVar('--proposed-accent');
    if (claim_type === 'UNKNOWN') return cssVar('--muted');
    return cssVar('--status-neutral');
  }

  function entityLabel(e) {
    var lines = [e.name];
    (e.fields || []).slice(0, 4).forEach(function (f) {
      lines.push('• ' + f.name + (f.note ? ' (' + f.note + ')' : ''));
    });
    return lines.join('\n');
  }

  function findComponent(model, id) {
    var list = model.components || [];
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) return list[i];
    }
    return null;
  }

  var cy = cytoscape({
    container: ctx.container,
    wheelSensitivity: 0.2,
    style: [
      {
        selector: 'node.entity',
        style: {
          shape: 'rectangle',
          'corner-radius': 6,
          width: 'label',
          height: 'label',
          padding: '12px',
          'text-wrap': 'wrap',
          'text-valign': 'center',
          'text-halign': 'center',
          label: 'data(label)',
          'font-size': 11,
          'font-family': 'ui-monospace, SFMono-Regular, Menlo, monospace',
          color: function (ele) {
            var claim = ele.data('claim_type');
            if (claim === 'OBSERVED') return '#ffffff';
            if (claim === 'PROPOSED') return cssVar('--proposed-accent');
            return cssVar('--text');
          },
          'background-color': function (ele) {
            return claimColor(ele.data('claim_type'));
          },
          'background-opacity': function (ele) {
            return claimOpacity(ele.data('claim_type'));
          },
          'border-width': 2,
          'border-color': function (ele) {
            return statusColor(ele.data('status'), ele.data('claim_type'));
          },
          'border-style': function (ele) {
            if (ele.data('claim_type') === 'PROPOSED') return 'dashed';
            return ele.data('confidence') === 'low' ? 'dashed' : 'solid';
          },
        },
      },
      {
        // A component that reads/writes a shown entity -- secondary
        // presence, not re-explaining app-layer confidence here.
        selector: 'node.touching-component',
        style: {
          shape: 'round-rectangle',
          'corner-radius': 8,
          width: 'label',
          height: 24,
          padding: '8px',
          label: 'data(label)',
          'font-size': 10,
          color: function () {
            return cssVar('--muted');
          },
          'background-color': function () {
            return cssVar('--surface-2');
          },
          'border-width': 1,
          'border-color': function () {
            return cssVar('--hairline');
          },
        },
      },
      {
        selector: 'edge.er-edge',
        style: {
          width: 2,
          'line-color': function () {
            return cssVar('--accent');
          },
          'target-arrow-color': function () {
            return cssVar('--accent');
          },
          'target-arrow-shape': 'triangle',
          'curve-style': 'bezier',
          label: 'data(label)',
          'font-size': 9,
          color: function () {
            return cssVar('--text-2');
          },
          'text-rotation': 0,
          'text-background-color': function () {
            return cssVar('--page');
          },
          'text-background-opacity': 0.92,
          'text-background-padding': 3,
        },
      },
      {
        // component -> entity reads/writes -- thin and dashed, secondary
        // to the ER relationships above.
        selector: 'edge.touch-edge',
        style: {
          width: 1,
          'line-style': 'dashed',
          'line-color': function () {
            return cssVar('--border');
          },
          'target-arrow-color': function () {
            return cssVar('--border');
          },
          'target-arrow-shape': 'triangle',
          'arrow-scale': 0.7,
          'curve-style': 'bezier',
        },
      },
      { selector: '.unfocused', style: { opacity: 0.35 } },
      { selector: 'node.onfocus', style: { 'border-width': 3 } },
    ],
  });

  cy.on('tap', 'node', function (evt) {
    ctx.onNodeClick(evt.target.id());
  });

  cy.on('tap', function (evt) {
    if (evt.target === cy && ctx.onClearFocus) ctx.onClearFocus();
  });

  function fit() {
    cy.fit(undefined, 50);
  }

  function relayout() {
    cy.layout({ name: 'dagre', rankDir: 'LR', nodeSep: 40, rankSep: 90, animate: false }).run();
    fit();
  }

  function render(model) {
    cy.elements().remove();

    var dataEntityIds = {};
    (model.data_entities || []).forEach(function (e) {
      dataEntityIds[e.id] = true;
      cy.add({
        group: 'nodes',
        data: {
          id: e.id,
          label: entityLabel(e),
          claim_type: e.claim_type,
          confidence: e.confidence,
          status: e.status,
        },
        classes: 'entity',
      });
    });

    var touchingComponentIds = {};
    var erEdges = [];
    var touchEdges = [];
    (model.relationships || []).forEach(function (r) {
      if (ER_KINDS[r.kind] && dataEntityIds[r.from] && dataEntityIds[r.to]) {
        erEdges.push(r);
      } else if (TOUCH_KINDS[r.kind] && (dataEntityIds[r.from] || dataEntityIds[r.to])) {
        touchEdges.push(r);
        touchingComponentIds[dataEntityIds[r.from] ? r.to : r.from] = true;
      }
    });

    Object.keys(touchingComponentIds).forEach(function (compId) {
      var c = findComponent(model, compId);
      if (c) {
        cy.add({ group: 'nodes', data: { id: c.id, label: c.name }, classes: 'touching-component' });
      }
    });

    erEdges.forEach(function (r) {
      cy.add({ group: 'edges', data: { id: r.id, source: r.from, target: r.to, label: r.kind }, classes: 'er-edge' });
    });
    touchEdges.forEach(function (r) {
      if (cy.getElementById(r.from).empty() || cy.getElementById(r.to).empty()) return;
      cy.add({ group: 'edges', data: { id: r.id, source: r.from, target: r.to }, classes: 'touch-edge' });
    });

    var isEmpty = (model.data_entities || []).length === 0;
    if (ctx.emptyEl) ctx.emptyEl.hidden = !isEmpty;
    if (isEmpty) return; // nothing to lay out

    relayout();
  }

  return { render: render, fit: fit };
};
