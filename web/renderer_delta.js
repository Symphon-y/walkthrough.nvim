/* walkthrough before/after delta view — renders a model/diff.lua result
 * (added/removed/changed/unchanged per section) as summary counts plus
 * cards for everything that isn't unchanged. Unchanged entities are
 * counted but not carded -- the point of a diff view is what moved, not
 * a second full listing of everything that didn't.
 *
 * ctx: { onEntityClick(id) }
 */
window.createDeltaView = function (container, ctx) {
  'use strict';

  function el(tag, className, text) {
    var e = document.createElement(tag);
    if (className) e.className = className;
    if (text != null) e.textContent = text;
    return e;
  }

  function nameOf(entity) {
    return entity.name || entity.question || entity.id;
  }

  function entityRow(kind, entity) {
    var row = el('div', 'delta-row delta-row-' + kind);
    row.appendChild(el('span', 'delta-marker delta-marker-' + kind, kind === 'added' ? '+' : '−'));
    if (entity.id) {
      var btn = el('button', 'delta-name', nameOf(entity));
      btn.addEventListener('click', function () {
        ctx.onEntityClick(entity.id);
      });
      row.appendChild(btn);
    } else {
      row.appendChild(el('span', 'delta-name', nameOf(entity)));
    }
    return row;
  }

  function fieldDiffRow(changed) {
    var row = el('div', 'delta-row delta-row-changed');
    row.appendChild(el('span', 'delta-marker delta-marker-changed', '~'));
    var body = el('div', 'delta-changed-body');
    var btn = el('button', 'delta-name', nameOf(changed.after));
    btn.addEventListener('click', function () {
      ctx.onEntityClick(changed.id);
    });
    body.appendChild(btn);

    changed.fields.forEach(function (field) {
      var before = changed.before[field];
      var after = changed.after[field];
      var line = el('div', 'delta-field');
      line.appendChild(el('span', 'delta-field-name', field + ': '));
      line.appendChild(el('span', 'delta-field-before', typeof before === 'string' ? before : JSON.stringify(before)));
      line.appendChild(el('span', 'delta-field-arrow', ' → '));
      line.appendChild(el('span', 'delta-field-after', typeof after === 'string' ? after : JSON.stringify(after)));
      body.appendChild(line);
    });
    row.appendChild(body);
    return row;
  }

  function section(title, diffSection) {
    var added = diffSection.added || [];
    var removed = diffSection.removed || [];
    var changed = diffSection.changed || [];
    var unchanged = diffSection.unchanged || [];

    var card = el('section', 'v-card');
    var head = el('div', 'delta-section-head');
    head.appendChild(el('h2', 'v-card-title', title));
    head.appendChild(
      el(
        'span',
        'delta-counts',
        added.length + ' added · ' + removed.length + ' removed · ' + changed.length + ' changed · ' + unchanged.length + ' unchanged'
      )
    );
    card.appendChild(head);

    if (added.length + removed.length + changed.length === 0) {
      card.appendChild(el('div', 'v-empty', 'No changes.'));
      container.appendChild(card);
      return;
    }

    added.forEach(function (e) {
      card.appendChild(entityRow('added', e));
    });
    removed.forEach(function (e) {
      card.appendChild(entityRow('removed', e));
    });
    changed.forEach(function (c) {
      card.appendChild(fieldDiffRow(c));
    });

    container.appendChild(card);
  }

  function render(diff) {
    container.innerHTML = '';
    if (!diff) {
      var empty = el('div', 'v-empty', 'No before/after diff attached to this session -- open with :WalkthroughDiff.');
      container.appendChild(empty);
      return;
    }
    section('Components', diff.components);
    section('Relationships', diff.relationships);
    section('Decisions', diff.decisions);
  }

  return { render: render };
};
