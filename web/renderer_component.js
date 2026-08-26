/* walkthrough component/architecture renderer — Cytoscape + dagre.
 *
 * Adapted from cartograph.nvim's renderer_cy.js: same library, same
 * general shape (a ctx object in, a small API out), but built around a
 * walkthrough model (components/relationships/groups, each carrying
 * claim_type/confidence/status) instead of a call graph, and rendered
 * once in full rather than incrementally merged in as LSP expansion
 * discovers more nodes -- a walkthrough is small and curated up front.
 *
 * Encoding (see dataviz skill / web/styles.css for the palette source):
 *   claim_type -> fill treatment: OBSERVED = solid, INFERRED = wash,
 *     UNKNOWN = outline only. Self-explanatory without reading a legend
 *     twice -- "how much is actually here" reads as "how much fill is there."
 *   status -> a thin ring (the fixed status palette), never the fill --
 *     two encodings on two different visual channels so they don't fight.
 *   confidence -> border style (dashed at low confidence) -- secondary,
 *     minor signal only.
 *
 * ctx: { container, onNodeClick(id), onClearFocus() }
 * returns: { ingest(model), applyFocus(overlay), fit }
 */
window.createComponentRenderer = function (ctx) {
  'use strict';

  function cssVar(name) {
    return getComputedStyle(document.body).getPropertyValue(name).trim();
  }

  var cy = cytoscape({
    container: ctx.container,
    wheelSensitivity: 0.2,
    style: [
      {
        selector: 'node.group',
        style: {
          shape: 'round-rectangle',
          'corner-radius': 14,
          'background-color': function () {
            return cssVar('--surface-2');
          },
          'background-opacity': 0.6,
          'border-width': 1,
          'border-color': function () {
            return cssVar('--hairline');
          },
          label: 'data(label)',
          color: function () {
            return cssVar('--muted');
          },
          'font-size': 10,
          'font-weight': 600,
          'text-transform': 'uppercase',
          'text-valign': 'top',
          'text-halign': 'left',
          'text-margin-x': 4,
          'text-margin-y': 10,
          'text-background-color': function () {
            return cssVar('--page');
          },
          'text-background-opacity': 1,
          'text-background-padding': 3,
          padding: '30px',
        },
      },
      {
        selector: 'node.entity',
        style: {
          shape: function (ele) {
            return ele.data('kind') === 'external' ? 'round-rectangle' : 'round-rectangle';
          },
          'corner-radius': 8,
          width: 'label',
          height: 34,
          padding: '14px',
          'text-max-width': '160px',
          'text-wrap': 'ellipsis',

          'background-color': function (ele) {
            var claim = ele.data('claim_type');
            return claim === 'UNKNOWN' ? 'transparent' : cssVar('--claim-solid');
          },
          'background-opacity': function (ele) {
            var claim = ele.data('claim_type');
            if (claim === 'OBSERVED') return 1;
            if (claim === 'INFERRED') return 0.16;
            return 0; // UNKNOWN: outline only
          },

          label: 'data(label)',
          color: function (ele) {
            return ele.data('claim_type') === 'OBSERVED' ? '#ffffff' : cssVar('--text');
          },
          'font-size': 12,
          'font-weight': 500,
          'text-valign': 'center',
          'text-halign': 'center',

          'border-width': function (ele) {
            return ele.data('status') && ele.data('status') !== 'proposed' && ele.data('status') !== 'unresolved' ? 2.5 : 1.5;
          },
          'border-color': function (ele) {
            return statusColor(ele.data('status'), ele.data('claim_type'));
          },
          'border-style': function (ele) {
            return ele.data('confidence') === 'low' ? 'dashed' : 'solid';
          },
          'border-opacity': 1,
        },
      },
      {
        selector: 'edge',
        style: {
          width: 1.5,
          'line-color': function () {
            return cssVar('--border');
          },
          'target-arrow-color': function () {
            return cssVar('--border');
          },
          'target-arrow-shape': 'triangle',
          'arrow-scale': 0.85,
          'curve-style': 'bezier',
          label: 'data(label)',
          'font-size': 10,
          color: function () {
            return cssVar('--text-2');
          },
          'text-rotation': 0, // never rotate: a rotated label through a compound stack is unreadable
          'text-background-color': function () {
            return cssVar('--page');
          },
          'text-background-opacity': 0.92,
          'text-background-padding': 3,
        },
      },
      // Dimmed floor kept high enough to still read shape + label -- 0.15
      // makes elements disappear entirely against a dark surface.
      { selector: '.unfocused', style: { opacity: 0.35 } },
      { selector: 'node.onfocus', style: { 'border-width': 3 } },
    ],
  });

  function statusColor(status, claim_type) {
    if (status === 'accepted') return cssVar('--status-good');
    if (status === 'challenged') return cssVar('--status-critical');
    if (status === 'corrected') return cssVar('--status-warning');
    // proposed / unresolved: no verdict yet -- a quiet neutral ring, not a
    // status color (those are reserved for an actual reviewed state).
    return claim_type === 'UNKNOWN' ? cssVar('--muted') : cssVar('--status-neutral');
  }

  cy.on('tap', 'node.entity', function (evt) {
    var id = evt.target.id();
    ctx.onNodeClick(id);
  });

  cy.on('tap', function (evt) {
    if (evt.target === cy && ctx.onClearFocus) ctx.onClearFocus();
  });

  function relayout() {
    cy.layout({ name: 'dagre', rankDir: 'TB', nodeSep: 55, rankSep: 90, animate: true, animationDuration: 200 }).run();
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
    cy.fit(undefined, 50);
  }

  return { ingest: ingest, applyFocus: applyFocus, fit: fit };
};
