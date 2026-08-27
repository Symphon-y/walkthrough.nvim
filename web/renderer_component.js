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
 *     PROPOSED (not built yet) is a different signal, not another step on
 *     that confidence ramp -- its own violet accent, always-dashed outline.
 *   status -> a thin ring (the fixed status palette), never the fill --
 *     two encodings on two different visual channels so they don't fight.
 *   confidence -> border style (dashed at low confidence) -- secondary,
 *     minor signal only. Overridden unconditionally for PROPOSED (see above).
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
            return claim === 'UNKNOWN' || claim === 'PROPOSED' ? 'transparent' : cssVar('--claim-solid');
          },
          'background-opacity': function (ele) {
            var claim = ele.data('claim_type');
            if (claim === 'OBSERVED') return 1;
            if (claim === 'INFERRED') return 0.16;
            return 0; // UNKNOWN / PROPOSED: outline only
          },

          label: 'data(label)',
          color: function (ele) {
            var claim = ele.data('claim_type');
            if (claim === 'OBSERVED') return '#ffffff';
            if (claim === 'PROPOSED') return cssVar('--proposed-accent');
            return cssVar('--text');
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
            // Not built yet is unconditional -- always dashed, regardless
            // of confidence (unlike the other three claim types).
            if (ele.data('claim_type') === 'PROPOSED') return 'dashed';
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
    // proposed / unresolved: no review verdict yet -- a quiet neutral ring,
    // not a status color (those are reserved for an actual reviewed
    // state) -- except PROPOSED claim_type, where the violet "not built
    // yet" signal stays visible even before anyone has reviewed it; that
    // one isn't a review-state color, it's the same entity-level signal
    // the fill/text already carry.
    if (claim_type === 'PROPOSED') return cssVar('--proposed-accent');
    if (claim_type === 'UNKNOWN') return cssVar('--muted');
    return cssVar('--status-neutral');
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

  /* Patch claim_type/confidence/status onto existing nodes (a correction
   * changes those, never the model's shape) without re-running layout --
   * a full re-ingest would jump the diagram on every accept/challenge. */
  function updateEntities(model) {
    (model.components || []).forEach(function (c) {
      var node = cy.getElementById(c.id);
      if (node.nonempty()) {
        node.data({ claim_type: c.claim_type, confidence: c.confidence, status: c.status });
      }
    });
  }

  return { ingest: ingest, applyFocus: applyFocus, updateEntities: updateEntities, fit: fit };
};
