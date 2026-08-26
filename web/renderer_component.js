/* walkthrough component/architecture renderer — Cytoscape + dagre.
 *
 * Adapted from cartograph.nvim's renderer_cy.js: same library, same
 * general shape (a ctx object in, a small API out), but built around a
 * walkthrough model (components/relationships/groups, each carrying
 * claim_type/confidence/status) instead of a call graph, and rendered
 * once in full rather than incrementally merged in as LSP expansion
 * discovers more nodes -- a walkthrough is small and curated up front.
 *
 * ctx: { container, onNodeClick(id), onClearFocus() }
 * returns: { ingest(model), applyFocus(overlay), fit }
 */
window.createComponentRenderer = function (ctx) {
  'use strict';

  var cy = cytoscape({
    container: ctx.container,
    wheelSensitivity: 0.2,
    style: [
      {
        selector: 'node.group',
        style: {
          shape: 'round-rectangle',
          'background-color': 'var(--panel)',
          'background-opacity': 0.6,
          'border-width': 1,
          'border-color': 'var(--border)',
          'border-style': 'dashed',
          label: 'data(label)',
          color: 'var(--muted)',
          'font-size': 11,
          'text-valign': 'top',
          'text-halign': 'center',
          'text-margin-y': 6,
          padding: '18px',
        },
      },
      {
        selector: 'node.entity',
        style: {
          shape: function (ele) {
            return ele.data('kind') === 'external' ? 'round-rectangle' : 'rectangle';
          },
          'background-color': function (ele) {
            return claimColor(ele.data('claim_type'));
          },
          'background-opacity': function (ele) {
            return confidenceOpacity(ele.data('confidence'));
          },
          label: 'data(label)',
          color: 'var(--text)',
          'font-size': 11,
          'text-valign': 'bottom',
          'text-margin-y': 6,
          width: 'label',
          height: 26,
          padding: '8px',
          'border-width': 2,
          'border-color': function (ele) {
            return statusColor(ele.data('status'));
          },
          'border-style': function (ele) {
            return ele.data('confidence') === 'low' ? 'dashed' : 'solid';
          },
        },
      },
      {
        selector: 'edge',
        style: {
          width: 1.5,
          'line-color': '#94a3b8',
          'target-arrow-color': '#94a3b8',
          'target-arrow-shape': 'triangle',
          'curve-style': 'bezier',
          label: 'data(label)',
          'font-size': 9,
          color: '#94a3b8',
          'text-rotation': 'autorotate',
          'text-background-color': 'var(--bg)',
          'text-background-opacity': 0.85,
          'text-background-padding': 2,
        },
      },
      { selector: '.unfocused', style: { opacity: 0.15 } },
      { selector: 'node.onfocus', style: { 'border-width': 4 } },
    ],
  });

  function claimColor(claim_type) {
    if (claim_type === 'OBSERVED') return getVar('--observed');
    if (claim_type === 'INFERRED') return getVar('--inferred');
    return getVar('--unknown');
  }

  function statusColor(status) {
    var key = '--status-' + (status || 'proposed');
    return getVar(key) || getVar('--status-proposed');
  }

  function confidenceOpacity(confidence) {
    if (confidence === 'high') return 1;
    if (confidence === 'medium') return 0.75;
    return 0.5;
  }

  function getVar(name) {
    return getComputedStyle(document.body).getPropertyValue(name).trim();
  }

  cy.on('tap', 'node.entity', function (evt) {
    var id = evt.target.id();
    ctx.onNodeClick(id);
  });

  cy.on('tap', function (evt) {
    if (evt.target === cy && ctx.onClearFocus) ctx.onClearFocus();
  });

  function relayout() {
    cy.layout({ name: 'dagre', rankDir: 'TB', nodeSep: 30, rankSep: 60, animate: true, animationDuration: 200 }).run();
  }

  /* Build the full element set from a walkthrough model. Called once on
   * load; a walkthrough's components/relationships don't change during a
   * session (corrections update status/claims in place via SSE, they
   * don't add/remove entities -- that only happens across revisions). */
  function ingest(model) {
    cy.elements().remove();

    (model.groups || []).forEach(function (g) {
      cy.add({ group: 'nodes', data: { id: g.id, label: g.name, parent: g.parent || undefined }, classes: 'group' });
    });

    (model.components || []).forEach(function (c) {
      cy.add({
        group: 'nodes',
        data: {
          id: c.id,
          label: c.name,
          kind: c.kind,
          claim_type: c.claim_type,
          confidence: c.confidence,
          status: c.status,
          parent: c.parent || c.group || undefined,
        },
        classes: 'entity',
      });
    });

    (model.relationships || []).forEach(function (r) {
      if (cy.getElementById(r.from).empty() || cy.getElementById(r.to).empty()) return;
      cy.add({
        group: 'edges',
        data: { id: r.id, source: r.from, target: r.to, label: r.data_shape || r.kind, kind: r.kind },
      });
    });

    relayout();
  }

  /* overlay: { active: {id:true,...}, dimmed: {id:true,...} } from
   * model/focus.lua's overlay(). Both nodes and edges may appear as keys
   * (focus.neighbors() includes relationship ids that touch the focused
   * node), so a plain id lookup works for both element kinds. */
  function applyFocus(overlay) {
    cy.elements().removeClass('unfocused onfocus');
    var active = (overlay && overlay.active) || {};
    var hasFocus = Object.keys(active).length > 0;
    if (!hasFocus) return;
    cy.elements().forEach(function (el) {
      if (el.hasClass('group')) return; // groups are never dimmed
      if (active[el.id()]) {
        el.addClass('onfocus');
      } else {
        el.addClass('unfocused');
      }
    });
  }

  function fit() {
    cy.fit(undefined, 40);
  }

  return { ingest: ingest, applyFocus: applyFocus, fit: fit };
};
