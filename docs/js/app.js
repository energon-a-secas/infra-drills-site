/* ============================================
   Local Drills — SPA Logic v2
   Refactored: event delegation, accessibility,
   collapsible tags, filter chips, view transitions.
   ============================================ */

(function () {
  'use strict';

  // --- State ---
  var data = null;
  var activeTag = null;
  var tagCloudExpanded = false;

  // Quiz state
  var quizState = {
    packId: null,
    questionIndex: 0,
    answers: {},
    revealed: {},
    matchSelections: {},
    score: 0
  };
  var quizClickHandler = null;
  var quizInputHandler = null;
  var quizKeyHandler = null;

  // --- Markdown setup ---
  function setupMarked() {
    marked.setOptions({
      highlight: function (code, lang) {
        if (lang && hljs.getLanguage(lang)) {
          return hljs.highlight(code, { language: lang }).value;
        }
        return hljs.highlightAuto(code).value;
      },
      breaks: false,
      gfm: true,
    });
  }

  // --- Utilities ---
  function humanize(name) {
    return name
      .replace(/[-_]/g, ' ')
      .replace(/\b\w/g, function (c) { return c.toUpperCase(); });
  }

  function escapeHtml(str) {
    var div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }

  function getHash() {
    return window.location.hash || '#/';
  }

  function parseRoute() {
    var hash = getHash();
    var drillMatch = hash.match(/^#\/drill\/(.+?)(\?.*)?$/);
    if (drillMatch) {
      return { view: 'drill', name: decodeURIComponent(drillMatch[1]) };
    }
    var quizMatch = hash.match(/^#\/quiz\/(.+?)(\?.*)?$/);
    if (quizMatch) {
      return { view: 'quiz', packId: decodeURIComponent(quizMatch[1]) };
    }
    if (hash.match(/^#\/quizzes/)) {
      return { view: 'quizzes', params: parseParams(hash) };
    }
    return { view: 'catalog', params: parseParams(hash) };
  }

  function parseParams(hash) {
    var params = {};
    var qIndex = hash.indexOf('?');
    if (qIndex === -1) return params;
    var qs = hash.substring(qIndex + 1);
    qs.split('&').forEach(function (pair) {
      var parts = pair.split('=');
      if (parts.length === 2) {
        params[decodeURIComponent(parts[0])] = decodeURIComponent(parts[1]);
      }
    });
    return params;
  }

  function buildHash(params) {
    var parts = [];
    Object.keys(params).forEach(function (key) {
      if (params[key]) {
        parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(params[key]));
      }
    });
    return '#/' + (parts.length ? '?' + parts.join('&') : '');
  }

  function copyToClipboard(text, btn) {
    navigator.clipboard.writeText(text).then(function () {
      var original = btn.textContent;
      btn.textContent = 'Copied!';
      btn.classList.add('copied');
      setTimeout(function () {
        btn.textContent = original;
        btn.classList.remove('copied');
      }, 2000);
    });
  }

  function getSectionLabel(section) {
    if (!data) return section;
    var s = data.sections.find(function (sec) { return sec.id === section; });
    return s ? s.label : section;
  }

  function getSectionIcon(section) {
    var icons = { aws: 'A', kubernetes: 'K', gitlab: 'G' };
    return icons[section] || '?';
  }

  function countBySection(sectionId) {
    return data.drills.filter(function (d) { return d.section === sectionId; }).length;
  }

  // --- Rendering helpers ---
  function renderMarkdown(md) {
    if (!md) return '<p class="empty-state">No content available.</p>';
    var html = marked.parse(md);
    // Wrap code blocks with copy buttons — using data attributes for event delegation
    html = html.replace(
      /<pre><code(?:\s+class="language-(\w+)")?>([\s\S]*?)<\/code><\/pre>/g,
      function (match, lang, code) {
        var langLabel = lang || 'text';
        return '<div class="code-block-wrapper">' +
          '<div class="code-block-header">' +
            '<span>' + escapeHtml(langLabel) + '</span>' +
            '<button class="copy-btn" data-copy="md" aria-label="Copy code">Copy</button>' +
          '</div>' +
          '<pre><code class="' + (lang ? 'language-' + lang : '') + '">' + code + '</code></pre>' +
        '</div>';
      }
    );
    return html;
  }

  function renderBadgeSection(section) {
    return '<span class="badge badge-section" data-section="' + escapeHtml(section) + '">' +
      escapeHtml(getSectionLabel(section)) + '</span>';
  }

  function renderBadgeDifficulty(difficulty) {
    return '<span class="badge badge-difficulty" data-difficulty="' + escapeHtml(difficulty) + '">' +
      escapeHtml(difficulty) + '</span>';
  }

  function renderBadgeStatus(status) {
    return '<span class="badge badge-status" data-status="' + escapeHtml(status) + '">' +
      escapeHtml(status) + '</span>';
  }

  function renderTag(tag, clickable) {
    if (clickable === undefined) clickable = true;
    var cls = 'tag' + (activeTag === tag ? ' active' : '');
    if (clickable) {
      return '<span class="' + cls + '" data-tag="' + escapeHtml(tag) + '" role="button" tabindex="0" aria-pressed="' + (activeTag === tag) + '">' + escapeHtml(tag) + '</span>';
    }
    return '<span class="tag">' + escapeHtml(tag) + '</span>';
  }

  // --- Section Stats ---
  function renderSectionStats(activeSection) {
    var html = '<div class="section-stats" role="group" aria-label="Section overview">';
    data.sections.forEach(function (s) {
      var count = countBySection(s.id);
      var isActive = activeSection === s.id;
      html += '<div class="stat-card' + (isActive ? ' active' : '') + '" data-section="' + s.id + '" role="button" tabindex="0" aria-label="Filter by ' + escapeHtml(s.label) + '">';
      html += '<div class="stat-icon" aria-hidden="true">' + getSectionIcon(s.id) + '</div>';
      html += '<div class="stat-info">';
      html += '<div class="stat-count">' + count + '</div>';
      html += '<div class="stat-label">' + escapeHtml(s.label) + ' drills</div>';
      html += '</div>';
      html += '</div>';
    });
    html += '</div>';
    return html;
  }

  // --- Active filter chips ---
  function renderActiveFilters(params) {
    var chips = [];
    if (params.section) {
      chips.push({ key: 'section', label: getSectionLabel(params.section), value: params.section });
    }
    if (params.difficulty) {
      chips.push({ key: 'difficulty', label: params.difficulty, value: params.difficulty });
    }
    if (params.status) {
      chips.push({ key: 'status', label: params.status, value: params.status });
    }
    if (params.tag) {
      chips.push({ key: 'tag', label: params.tag, value: params.tag });
    }
    if (params.search) {
      chips.push({ key: 'search', label: '"' + params.search + '"', value: params.search });
    }

    if (chips.length === 0) return '';

    var html = '<div class="active-filters" role="group" aria-label="Active filters">';
    chips.forEach(function (chip) {
      html += '<span class="filter-chip">';
      html += escapeHtml(chip.label);
      html += '<button class="filter-chip-remove" data-remove-filter="' + chip.key + '" aria-label="Remove ' + escapeHtml(chip.label) + ' filter">&times;</button>';
      html += '</span>';
    });
    html += '</div>';
    return html;
  }

  // --- Catalog View ---
  function renderCatalog(params) {
    var app = document.getElementById('app');
    var section = params.section || '';
    var difficulty = params.difficulty || '';
    var status = params.status || '';
    var search = params.search || '';
    activeTag = params.tag || null;

    var html = '<div class="view-enter">';

    html += '<div class="catalog-header">' +
      '<h1 class="catalog-title">Troubleshooting Challenges</h1>' +
      '<p class="catalog-subtitle">Practice AWS, Kubernetes & GitLab CI/CD troubleshooting locally.</p>' +
    '</div>';

    // Section stats
    html += renderSectionStats(section);

    // Filters
    html += '<div class="filters" role="search" aria-label="Filter drills">';
    html += '<div class="search-wrapper">';
    html += '<span class="search-icon" aria-hidden="true">&#128269;</span>';
    html += '<input type="text" class="search-input" id="search-input" placeholder="Search drills..." value="' + escapeHtml(search) + '" aria-label="Search drills">';
    html += '<button class="search-clear' + (search ? ' visible' : '') + '" id="search-clear" aria-label="Clear search">&times;</button>';
    html += '</div>';

    html += '<select class="filter-select" id="filter-section" aria-label="Filter by section">';
    html += '<option value="">All Sections</option>';
    data.sections.forEach(function (s) {
      var count = countBySection(s.id);
      html += '<option value="' + s.id + '"' + (section === s.id ? ' selected' : '') + '>' + escapeHtml(s.label) + ' (' + count + ')</option>';
    });
    html += '</select>';

    html += '<select class="filter-select" id="filter-difficulty" aria-label="Filter by difficulty">';
    html += '<option value="">All Levels</option>';
    ['beginner', 'intermediate', 'advanced'].forEach(function (d) {
      html += '<option value="' + d + '"' + (difficulty === d ? ' selected' : '') + '>' + d.charAt(0).toUpperCase() + d.slice(1) + '</option>';
    });
    html += '</select>';

    html += '<select class="filter-select" id="filter-status" aria-label="Filter by status">';
    html += '<option value="">All Status</option>';
    ['complete', 'incomplete', 'stub'].forEach(function (s) {
      html += '<option value="' + s + '"' + (status === s ? ' selected' : '') + '>' + s.charAt(0).toUpperCase() + s.slice(1) + '</option>';
    });
    html += '</select>';
    html += '</div>';

    // Active filter chips
    html += renderActiveFilters(params);

    // Tag cloud — collapsible
    html += '<div class="tag-cloud">';
    html += '<button class="tag-cloud-toggle' + (tagCloudExpanded ? ' expanded' : '') + '" id="tag-cloud-toggle" aria-expanded="' + tagCloudExpanded + '">';
    html += 'Tags (' + data.tags.length + ') <span class="arrow" aria-hidden="true">&#9660;</span>';
    html += '</button>';
    html += '<div class="tag-filters' + (tagCloudExpanded ? ' expanded' : '') + '" id="tag-filters" role="group" aria-label="Filter by tag">';
    data.tags.forEach(function (t) {
      html += renderTag(t, true);
    });
    html += '</div>';
    html += '</div>';

    // Filter drills
    var filtered = data.drills.filter(function (d) {
      if (section && d.section !== section) return false;
      if (difficulty && d.difficulty !== difficulty) return false;
      if (status && d.status !== status) return false;
      if (activeTag && d.tags.indexOf(activeTag) === -1) return false;
      if (search) {
        var q = search.toLowerCase();
        var haystack = (d.name + ' ' + d.description + ' ' + d.tags.join(' ') + ' ' + d.service).toLowerCase();
        if (haystack.indexOf(q) === -1) return false;
      }
      return true;
    });

    // Results count
    html += '<div class="results-count" aria-live="polite">Showing ' + filtered.length + ' of ' + data.drills.length + ' drills</div>';

    // Card grid
    if (filtered.length === 0) {
      html += '<div class="no-results">';
      html += '<p class="no-results-title">No drills match your filters</p>';
      html += '<p>Try adjusting your search or filters.</p>';
      html += '</div>';
    } else {
      html += '<div class="card-grid" role="list">';
      filtered.forEach(function (drill) {
        var fileCount = drill.files ? drill.files.length : 0;
        html += '<div class="drill-card" data-section="' + escapeHtml(drill.section) + '" data-drill="' + escapeHtml(drill.name) + '" role="listitem" tabindex="0" aria-label="' + escapeHtml(humanize(drill.name)) + ' — ' + escapeHtml(drill.difficulty) + '">';
        html += '<div class="card-header">';
        html += '<span class="card-name">' + escapeHtml(humanize(drill.name)) + '</span>';
        html += renderBadgeDifficulty(drill.difficulty);
        html += '</div>';
        html += '<div class="card-description">' + escapeHtml(drill.description) + '</div>';
        html += '<div class="card-footer">';
        html += '<div class="card-tags">';
        html += renderBadgeSection(drill.section);
        drill.tags.slice(0, 3).forEach(function (t) {
          html += renderTag(t, false);
        });
        html += '</div>';
        if (fileCount > 0) {
          html += '<span class="card-file-count">' + fileCount + ' files</span>';
        }
        html += '</div>';
        html += '</div>';
      });
      html += '</div>';
    }

    html += '</div>'; // view-enter

    app.innerHTML = html;
    bindCatalogEvents(params);
  }

  function bindCatalogEvents(params) {
    var app = document.getElementById('app');

    // Search with debounce
    var searchInput = document.getElementById('search-input');
    var searchClear = document.getElementById('search-clear');
    var debounceTimer;

    searchInput.addEventListener('input', function () {
      searchClear.classList.toggle('visible', searchInput.value.length > 0);
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(updateFilters, 250);
    });

    searchClear.addEventListener('click', function () {
      searchInput.value = '';
      searchClear.classList.remove('visible');
      searchInput.focus();
      updateFilters();
    });

    // Select filters
    ['filter-section', 'filter-difficulty', 'filter-status'].forEach(function (id) {
      document.getElementById(id).addEventListener('change', updateFilters);
    });

    // Tag cloud toggle
    document.getElementById('tag-cloud-toggle').addEventListener('click', function () {
      tagCloudExpanded = !tagCloudExpanded;
      this.classList.toggle('expanded', tagCloudExpanded);
      this.setAttribute('aria-expanded', tagCloudExpanded);
      document.getElementById('tag-filters').classList.toggle('expanded', tagCloudExpanded);
    });

    // Event delegation for the whole app area
    app.addEventListener('click', function (e) {
      // Tag clicks in tag cloud
      var tagEl = e.target.closest('#tag-filters .tag');
      if (tagEl) {
        var tag = tagEl.dataset.tag;
        activeTag = (activeTag === tag) ? null : tag;
        updateFilters();
        return;
      }

      // Section stat card clicks
      var statCard = e.target.closest('.stat-card');
      if (statCard) {
        var sec = statCard.dataset.section;
        var filterSection = document.getElementById('filter-section');
        if (filterSection.value === sec) {
          filterSection.value = '';
        } else {
          filterSection.value = sec;
        }
        updateFilters();
        return;
      }

      // Filter chip remove
      var chipRemove = e.target.closest('.filter-chip-remove');
      if (chipRemove) {
        removeFilter(chipRemove.dataset.removeFilter);
        return;
      }

      // Drill card clicks (but not tags inside cards)
      var card = e.target.closest('.drill-card');
      if (card) {
        window.location.hash = '#/drill/' + encodeURIComponent(card.dataset.drill);
        return;
      }
    });

    // Keyboard support for cards and stat cards
    app.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' || e.key === ' ') {
        var card = e.target.closest('.drill-card');
        if (card) {
          e.preventDefault();
          window.location.hash = '#/drill/' + encodeURIComponent(card.dataset.drill);
          return;
        }

        var statCard = e.target.closest('.stat-card');
        if (statCard) {
          e.preventDefault();
          statCard.click();
          return;
        }

        var tagEl = e.target.closest('.tag[data-tag]');
        if (tagEl) {
          e.preventDefault();
          tagEl.click();
          return;
        }
      }
    });
  }

  function removeFilter(key) {
    var searchInput = document.getElementById('search-input');
    var params = {};

    if (key !== 'search' && searchInput && searchInput.value) params.search = searchInput.value;
    if (key !== 'section') {
      var sec = document.getElementById('filter-section');
      if (sec && sec.value) params.section = sec.value;
    }
    if (key !== 'difficulty') {
      var diff = document.getElementById('filter-difficulty');
      if (diff && diff.value) params.difficulty = diff.value;
    }
    if (key !== 'status') {
      var st = document.getElementById('filter-status');
      if (st && st.value) params.status = st.value;
    }
    if (key !== 'tag' && activeTag) params.tag = activeTag;
    if (key === 'tag') activeTag = null;

    window.location.hash = buildHash(params);
  }

  function updateFilters() {
    var params = {};
    var searchInput = document.getElementById('search-input');
    if (searchInput && searchInput.value) params.search = searchInput.value;

    var section = document.getElementById('filter-section');
    if (section && section.value) params.section = section.value;

    var difficulty = document.getElementById('filter-difficulty');
    if (difficulty && difficulty.value) params.difficulty = difficulty.value;

    var status = document.getElementById('filter-status');
    if (status && status.value) params.status = status.value;

    if (activeTag) params.tag = activeTag;

    window.location.hash = buildHash(params);
  }

  // --- Drill Detail View ---
  function renderDrill(name) {
    var app = document.getElementById('app');
    var drill = data.drills.find(function (d) { return d.name === name; });

    if (!drill) {
      app.innerHTML = '<div class="no-results"><p class="no-results-title">Drill not found</p>' +
        '<p><a href="#/">Back to catalog</a></p></div>';
      return;
    }

    var html = '<div class="view-enter">';

    // Breadcrumb
    html += '<nav class="breadcrumb" aria-label="Breadcrumb">';
    html += '<a href="#/">Catalog</a>';
    html += '<span class="breadcrumb-sep" aria-hidden="true">/</span>';
    html += '<a href="' + buildHash({ section: drill.section }) + '">' + escapeHtml(getSectionLabel(drill.section)) + '</a>';
    html += '<span class="breadcrumb-sep" aria-hidden="true">/</span>';
    html += '<span class="breadcrumb-current">' + escapeHtml(drill.name) + '</span>';
    html += '</nav>';

    html += '<div class="drill-detail">';

    // Main content
    html += '<div class="detail-main">';

    // Header
    html += '<div class="detail-header">';
    html += '<h1 class="detail-name">' + escapeHtml(humanize(drill.name)) + '</h1>';
    html += '<div class="detail-meta">';
    html += renderBadgeSection(drill.section);
    html += renderBadgeDifficulty(drill.difficulty);
    html += renderBadgeStatus(drill.status);
    html += '</div>';
    html += '<p class="detail-description">' + escapeHtml(drill.description) + '</p>';
    if (drill.tags.length) {
      html += '<div class="detail-tags">';
      drill.tags.forEach(function (t) {
        html += '<a class="tag" href="' + buildHash({ tag: t }) + '">' + escapeHtml(t) + '</a>';
      });
      html += '</div>';
    }
    html += '</div>';

    // Tabs
    html += '<div class="tabs" role="tablist">';
    html += '<button class="tab-btn active" data-tab="problem" role="tab" aria-selected="true" aria-controls="tab-problem">Problem</button>';
    if (drill.files && drill.files.length) {
      html += '<button class="tab-btn" data-tab="files" role="tab" aria-selected="false" aria-controls="tab-files">Files (' + drill.files.length + ')</button>';
    }
    html += '<button class="tab-btn" data-tab="solution" role="tab" aria-selected="false" aria-controls="tab-solution">Solution</button>';
    html += '</div>';

    // Problem tab
    html += '<div class="tab-content active" id="tab-problem" role="tabpanel">';
    html += '<div class="markdown-body">' + renderMarkdown(drill.readme) + '</div>';
    html += '</div>';

    // Files tab
    if (drill.files && drill.files.length) {
      html += '<div class="tab-content" id="tab-files" role="tabpanel">';
      html += '<div class="file-tabs">';
      drill.files.forEach(function (file, i) {
        html += '<button class="file-tab-btn' + (i === 0 ? ' active' : '') + '" data-file-index="' + i + '">' +
          escapeHtml(file.name) + '</button>';
      });
      html += '</div>';

      drill.files.forEach(function (file, i) {
        html += '<div class="file-content' + (i === 0 ? ' active' : '') + '" data-file-index="' + i + '">';
        var highlighted = '';
        if (file.language && hljs.getLanguage(file.language)) {
          highlighted = hljs.highlight(file.content, { language: file.language }).value;
        } else {
          highlighted = escapeHtml(file.content);
        }
        html += '<div class="code-block-wrapper">';
        html += '<div class="code-block-header">';
        html += '<span>' + escapeHtml(file.name) + '</span>';
        html += '<button class="copy-btn" data-copy="file" data-file-index="' + i + '" aria-label="Copy ' + escapeHtml(file.name) + '">Copy</button>';
        html += '</div>';
        html += '<pre><code class="' + (file.language ? 'language-' + escapeHtml(file.language) : '') + '">' + highlighted + '</code></pre>';
        html += '</div>';
        html += '</div>';
      });
      html += '</div>';
    }

    // Solution tab
    html += '<div class="tab-content" id="tab-solution" role="tabpanel">';
    if (drill.solution) {
      html += '<button class="spoiler-btn" id="reveal-solution" aria-expanded="false">&#128274; Reveal Solution</button>';
      html += '<div class="spoiler-content" id="solution-content">';
      html += '<div class="markdown-body">' + renderMarkdown(drill.solution) + '</div>';
      html += '</div>';
    } else {
      html += '<div class="empty-state">Solution not available yet.</div>';
    }
    html += '</div>';

    html += '</div>'; // detail-main

    // Sidebar
    html += '<div class="detail-sidebar">';
    html += '<a href="#/" class="back-btn" aria-label="Back to catalog">&larr; Back to Catalog</a>';

    // Get Started card
    var hasInit = drill.files && drill.files.some(function (f) { return f.name === 'lab-initialization.sh'; });
    if (hasInit) {
      var setupSteps = [
        ['1. Clone', 'git clone https://github.com/energon-a-secas/local-drills.git'],
        ['2. Navigate', 'cd local-drills/' + drill.section + '/' + drill.name],
        ['3. Initialize', 'bash lab-initialization.sh']
      ];
      html += '<div class="sidebar-card">';
      html += '<div class="sidebar-title">Get Started</div>';
      setupSteps.forEach(function (step) {
        html += '<div class="setup-step">';
        html += '<div class="setup-step-label">' + escapeHtml(step[0]) + '</div>';
        html += '<div class="code-block-wrapper">';
        html += '<div class="code-block-header">';
        html += '<span>bash</span>';
        html += '<button class="copy-btn" data-copy="md" aria-label="Copy ' + escapeHtml(step[0]) + '">Copy</button>';
        html += '</div>';
        html += '<pre><code class="language-bash">' + escapeHtml(step[1]) + '</code></pre>';
        html += '</div>';
        html += '</div>';
      });
      html += '</div>';
    }

    if (drill.prerequisites && drill.prerequisites.length) {
      html += '<div class="sidebar-card">';
      html += '<div class="sidebar-title">Prerequisites</div>';
      drill.prerequisites.forEach(function (prereq) {
        html += '<a class="sidebar-link" href="#/drill/' + encodeURIComponent(prereq) + '">' +
          escapeHtml(humanize(prereq)) + '</a>';
      });
      html += '</div>';
    }

    // Info card
    html += '<div class="sidebar-card">';
    html += '<div class="sidebar-title">Info</div>';
    html += '<div class="sidebar-item"><span class="sidebar-item-label">Section</span><span class="sidebar-item-value">' + escapeHtml(getSectionLabel(drill.section)) + '</span></div>';
    html += '<div class="sidebar-item"><span class="sidebar-item-label">Service</span><span class="sidebar-item-value">' + escapeHtml(drill.service.toUpperCase()) + '</span></div>';
    html += '<div class="sidebar-item"><span class="sidebar-item-label">Difficulty</span><span class="sidebar-item-value">' + escapeHtml(drill.difficulty) + '</span></div>';
    html += '<div class="sidebar-item"><span class="sidebar-item-label">Status</span><span class="sidebar-item-value">' + escapeHtml(drill.status) + '</span></div>';
    if (drill.files) {
      html += '<div class="sidebar-item"><span class="sidebar-item-label">Files</span><span class="sidebar-item-value">' + drill.files.length + '</span></div>';
    }
    html += '</div>';

    // Related quizzes
    if (data.quizzes && data.quizzes.length) {
      var relatedQuizzes = data.quizzes.filter(function (q) {
        return q.related_drills && q.related_drills.indexOf(drill.name) !== -1;
      });
      if (relatedQuizzes.length) {
        html += '<div class="sidebar-card">';
        html += '<div class="sidebar-title">Related Quizzes</div>';
        relatedQuizzes.forEach(function (q) {
          html += '<a class="sidebar-link" href="#/quiz/' + encodeURIComponent(q.id) + '">' +
            escapeHtml(q.topic) + ' (' + q.questions.length + 'Q)</a>';
        });
        html += '</div>';
      }
    }

    html += '</div>'; // detail-sidebar
    html += '</div>'; // drill-detail
    html += '</div>'; // view-enter

    app.innerHTML = html;
    bindDetailEvents(drill);
  }

  function bindDetailEvents(drill) {
    var app = document.getElementById('app');

    // Event delegation for all detail interactions
    app.addEventListener('click', function handler(e) {
      // Main tab buttons
      var tabBtn = e.target.closest('.tabs .tab-btn');
      if (tabBtn) {
        document.querySelectorAll('.tabs .tab-btn').forEach(function (b) {
          b.classList.remove('active');
          b.setAttribute('aria-selected', 'false');
        });
        document.querySelectorAll('.tab-content').forEach(function (c) { c.classList.remove('active'); });
        tabBtn.classList.add('active');
        tabBtn.setAttribute('aria-selected', 'true');
        var tabContent = document.getElementById('tab-' + tabBtn.dataset.tab);
        if (tabContent) tabContent.classList.add('active');
        return;
      }

      // File tab buttons
      var fileTabBtn = e.target.closest('.file-tab-btn');
      if (fileTabBtn) {
        document.querySelectorAll('.file-tab-btn').forEach(function (b) { b.classList.remove('active'); });
        document.querySelectorAll('.file-content').forEach(function (c) { c.classList.remove('active'); });
        fileTabBtn.classList.add('active');
        var idx = fileTabBtn.dataset.fileIndex;
        var content = document.querySelector('.file-content[data-file-index="' + idx + '"]');
        if (content) content.classList.add('active');
        return;
      }

      // Copy buttons — handles both markdown code blocks and file tab copies
      var copyBtn = e.target.closest('.copy-btn');
      if (copyBtn) {
        if (copyBtn.dataset.copy === 'file' && drill.files) {
          var fileIdx = parseInt(copyBtn.dataset.fileIndex, 10);
          copyToClipboard(drill.files[fileIdx].content, copyBtn);
        } else {
          // Markdown code block copy
          var wrapper = copyBtn.closest('.code-block-wrapper');
          if (wrapper) {
            var codeEl = wrapper.querySelector('code');
            copyToClipboard(codeEl.textContent, copyBtn);
          }
        }
        return;
      }

      // Reveal solution
      var revealBtn = e.target.closest('#reveal-solution');
      if (revealBtn) {
        var solutionContent = document.getElementById('solution-content');
        solutionContent.classList.add('revealed');
        revealBtn.setAttribute('aria-expanded', 'true');
        revealBtn.style.display = 'none';
        return;
      }
    });
  }

  // --- Quiz Helpers ---
  function resetQuizState(packId) {
    quizState = {
      packId: packId,
      questionIndex: 0,
      answers: {},
      revealed: {},
      matchSelections: {},
      score: 0
    };
  }

  function getQuizPack(packId) {
    if (!data || !data.quizzes) return null;
    return data.quizzes.find(function (q) { return q.id === packId; });
  }

  function countQuizzesBySection(sectionId) {
    if (!data || !data.quizzes) return 0;
    return data.quizzes.filter(function (q) { return q.section === sectionId; }).length;
  }

  function countQuestionsBySection(sectionId) {
    if (!data || !data.quizzes) return 0;
    return data.quizzes
      .filter(function (q) { return q.section === sectionId; })
      .reduce(function (sum, q) { return sum + q.questions.length; }, 0);
  }

  function getQuestionTypeBreakdown(pack) {
    var counts = { diagnose: 0, complete: 0, match: 0 };
    pack.questions.forEach(function (q) {
      if (counts[q.type] !== undefined) counts[q.type]++;
    });
    return counts;
  }

  function checkCompleteAnswer(userAnswer, question) {
    var trimmed = userAnswer.trim().toLowerCase();
    if (!trimmed) return false;
    if (question.answer.toLowerCase() === trimmed) return true;
    if (question.accept) {
      return question.accept.some(function (a) {
        return a.toLowerCase() === trimmed;
      });
    }
    return false;
  }

  function checkMatchAnswer(userPairs, correctPairs) {
    if (userPairs.length !== correctPairs.length) return false;
    var sorted = userPairs.slice().sort(function (a, b) {
      return a[0] - b[0] || a[1] - b[1];
    });
    var correctSorted = correctPairs.slice().sort(function (a, b) {
      return a[0] - b[0] || a[1] - b[1];
    });
    return sorted.every(function (pair, i) {
      return pair[0] === correctSorted[i][0] && pair[1] === correctSorted[i][1];
    });
  }

  function isMatchPairCorrect(leftIdx, rightIdx, correctPairs) {
    return correctPairs.some(function (p) {
      return p[0] === leftIdx && p[1] === rightIdx;
    });
  }

  // --- Quiz Catalog View ---
  function renderQuizCatalog(params) {
    var app = document.getElementById('app');
    var section = (params && params.section) || '';
    var difficulty = (params && params.difficulty) || '';
    var quizzes = data.quizzes || [];

    var html = '<div class="view-enter">';

    html += '<div class="catalog-header">';
    html += '<h1 class="catalog-title">Knowledge Quizzes</h1>';
    html += '<p class="catalog-subtitle">Test your AWS, Kubernetes & GitLab CI/CD knowledge. ' + data.meta.question_count + ' questions across ' + data.meta.quiz_count + ' packs.</p>';
    html += '</div>';

    // Section stats for quizzes
    html += '<div class="section-stats" role="group" aria-label="Quiz section overview">';
    data.sections.forEach(function (s) {
      var qCount = countQuestionsBySection(s.id);
      var pCount = countQuizzesBySection(s.id);
      var isActive = section === s.id;
      html += '<div class="stat-card' + (isActive ? ' active' : '') + '" data-quiz-section="' + s.id + '" role="button" tabindex="0" aria-label="Filter by ' + escapeHtml(s.label) + '">';
      html += '<div class="stat-icon" aria-hidden="true">' + getSectionIcon(s.id) + '</div>';
      html += '<div class="stat-info">';
      html += '<div class="stat-count">' + qCount + '</div>';
      html += '<div class="stat-label">' + escapeHtml(s.label) + ' questions</div>';
      html += '</div>';
      html += '</div>';
    });
    html += '</div>';

    // Filters
    html += '<div class="quiz-filters">';
    html += '<select class="filter-select" id="quiz-filter-section" aria-label="Filter by section">';
    html += '<option value="">All Sections</option>';
    data.sections.forEach(function (s) {
      html += '<option value="' + s.id + '"' + (section === s.id ? ' selected' : '') + '>' + escapeHtml(s.label) + '</option>';
    });
    html += '</select>';
    html += '<select class="filter-select" id="quiz-filter-difficulty" aria-label="Filter by difficulty">';
    html += '<option value="">All Levels</option>';
    ['beginner', 'intermediate', 'advanced'].forEach(function (d) {
      html += '<option value="' + d + '"' + (difficulty === d ? ' selected' : '') + '>' + d.charAt(0).toUpperCase() + d.slice(1) + '</option>';
    });
    html += '</select>';
    html += '<a href="#/" class="quiz-back-link">&larr; Back to Drills</a>';
    html += '</div>';

    // Filter quizzes
    var filtered = quizzes.filter(function (q) {
      if (section && q.section !== section) return false;
      if (difficulty && q.difficulty !== difficulty) return false;
      return true;
    });

    html += '<div class="results-count" aria-live="polite">Showing ' + filtered.length + ' of ' + quizzes.length + ' quiz packs</div>';

    if (filtered.length === 0) {
      html += '<div class="no-results"><p class="no-results-title">No quizzes match your filters</p></div>';
    } else {
      html += '<div class="card-grid" role="list">';
      filtered.forEach(function (pack) {
        var types = getQuestionTypeBreakdown(pack);
        html += '<div class="quiz-card" data-section="' + escapeHtml(pack.section) + '" data-pack="' + escapeHtml(pack.id) + '" role="listitem" tabindex="0">';
        html += '<div class="card-header">';
        html += '<span class="card-name">' + escapeHtml(pack.topic) + '</span>';
        html += renderBadgeDifficulty(pack.difficulty);
        html += '</div>';
        html += '<div class="quiz-card-meta">';
        html += renderBadgeSection(pack.section);
        html += '<span class="quiz-q-count">' + pack.questions.length + ' questions</span>';
        html += '</div>';
        html += '<div class="quiz-type-breakdown">';
        if (types.diagnose > 0) html += '<span class="quiz-type-tag" data-type="diagnose">MC: ' + types.diagnose + '</span>';
        if (types.complete > 0) html += '<span class="quiz-type-tag" data-type="complete">Fill: ' + types.complete + '</span>';
        if (types.match > 0) html += '<span class="quiz-type-tag" data-type="match">Match: ' + types.match + '</span>';
        html += '</div>';
        if (pack.related_drills && pack.related_drills.length) {
          html += '<div class="quiz-related">';
          pack.related_drills.forEach(function (drill) {
            html += '<a class="quiz-related-link" href="#/drill/' + encodeURIComponent(drill) + '">' + escapeHtml(humanize(drill)) + '</a>';
          });
          html += '</div>';
        }
        html += '<button class="quiz-start-btn" data-pack="' + escapeHtml(pack.id) + '">Start Quiz</button>';
        html += '</div>';
      });
      html += '</div>';
    }

    html += '</div>';
    app.innerHTML = html;
    bindQuizCatalogEvents(params);
  }

  function bindQuizCatalogEvents(params) {
    var app = document.getElementById('app');

    ['quiz-filter-section', 'quiz-filter-difficulty'].forEach(function (id) {
      var el = document.getElementById(id);
      if (el) {
        el.addEventListener('change', function () {
          var p = {};
          var sec = document.getElementById('quiz-filter-section');
          var diff = document.getElementById('quiz-filter-difficulty');
          if (sec && sec.value) p.section = sec.value;
          if (diff && diff.value) p.difficulty = diff.value;
          var parts = [];
          Object.keys(p).forEach(function (key) {
            parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(p[key]));
          });
          window.location.hash = '#/quizzes' + (parts.length ? '?' + parts.join('&') : '');
        });
      }
    });

    app.addEventListener('click', function (e) {
      var sectionCard = e.target.closest('[data-quiz-section]');
      if (sectionCard) {
        var sec = sectionCard.dataset.quizSection;
        var filterEl = document.getElementById('quiz-filter-section');
        if (filterEl) {
          filterEl.value = filterEl.value === sec ? '' : sec;
          filterEl.dispatchEvent(new Event('change'));
        }
        return;
      }

      var startBtn = e.target.closest('.quiz-start-btn');
      if (startBtn) {
        e.stopPropagation();
        window.location.hash = '#/quiz/' + encodeURIComponent(startBtn.dataset.pack);
        return;
      }

      var card = e.target.closest('.quiz-card');
      if (card && !e.target.closest('.quiz-related-link')) {
        window.location.hash = '#/quiz/' + encodeURIComponent(card.dataset.pack);
        return;
      }
    });

    app.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' || e.key === ' ') {
        var card = e.target.closest('.quiz-card');
        if (card) {
          e.preventDefault();
          window.location.hash = '#/quiz/' + encodeURIComponent(card.dataset.pack);
        }
      }
    });
  }

  // --- Quiz Session View ---
  function renderQuizSession(packId) {
    var app = document.getElementById('app');
    var pack = getQuizPack(packId);

    if (!pack) {
      app.innerHTML = '<div class="no-results"><p class="no-results-title">Quiz not found</p>' +
        '<p><a href="#/quizzes">Back to quizzes</a></p></div>';
      return;
    }

    if (quizState.packId !== packId) {
      resetQuizState(packId);
    }

    var total = pack.questions.length;
    var idx = quizState.questionIndex;

    // Show score summary if done
    if (idx >= total) {
      renderQuizScore(pack);
      return;
    }

    var question = pack.questions[idx];
    var isRevealed = quizState.revealed[question.id];

    var html = '<div class="view-enter">';

    // Breadcrumb
    html += '<nav class="breadcrumb" aria-label="Breadcrumb">';
    html += '<a href="#/quizzes">Quizzes</a>';
    html += '<span class="breadcrumb-sep" aria-hidden="true">/</span>';
    html += '<span class="breadcrumb-current">' + escapeHtml(pack.topic) + '</span>';
    html += '</nav>';

    // Progress bar
    var progress = ((idx) / total) * 100;
    html += '<div class="quiz-progress">';
    html += '<div class="quiz-progress-info">';
    html += '<span>Question ' + (idx + 1) + ' of ' + total + '</span>';
    html += renderBadgeSection(pack.section);
    html += '</div>';
    html += '<div class="quiz-progress-bar" role="progressbar" aria-valuenow="' + (idx + 1) + '" aria-valuemin="1" aria-valuemax="' + total + '">';
    html += '<div class="quiz-progress-fill" style="width:' + progress + '%"></div>';
    html += '</div>';
    html += '</div>';

    // Question container
    html += '<div class="quiz-question-container">';

    // Question type badge
    var typeLabels = { diagnose: 'Multiple Choice', complete: 'Fill in the Blank', match: 'Match Pairs' };
    html += '<span class="quiz-type-badge" data-type="' + question.type + '">' + (typeLabels[question.type] || question.type) + '</span>';

    // Prompt
    html += '<div class="quiz-prompt markdown-body">' + renderMarkdown(question.prompt) + '</div>';

    // Type-specific UI
    if (question.type === 'diagnose') {
      html += renderDiagnoseQuestion(question, isRevealed);
    } else if (question.type === 'complete') {
      html += renderCompleteQuestion(question, isRevealed);
    } else if (question.type === 'match') {
      html += renderMatchQuestion(question, isRevealed);
    }

    // Feedback
    if (isRevealed) {
      var isCorrect = getAnswerCorrectness(question);
      html += '<div class="quiz-feedback ' + (isCorrect ? 'correct' : 'incorrect') + '">';
      html += '<div class="quiz-feedback-header">' + (isCorrect ? 'Correct!' : 'Incorrect') + '</div>';
      if (question.explanation) {
        html += '<div class="quiz-feedback-explanation markdown-body">' + renderMarkdown(question.explanation) + '</div>';
      }
      html += '</div>';

      html += '<button class="quiz-next-btn">' + (idx + 1 < total ? 'Next Question' : 'See Results') + '</button>';
    }

    html += '</div>'; // quiz-question-container
    html += '</div>'; // view-enter

    app.innerHTML = html;
    bindQuizSessionEvents(pack);
  }

  function getAnswerCorrectness(question) {
    if (question.type === 'diagnose') {
      return quizState.answers[question.id] === question.answer;
    } else if (question.type === 'complete') {
      return checkCompleteAnswer(quizState.answers[question.id] || '', question);
    } else if (question.type === 'match') {
      var sel = quizState.matchSelections[question.id];
      if (!sel) return false;
      return checkMatchAnswer(sel.pairs || [], question.pairs);
    }
    return false;
  }

  function renderDiagnoseQuestion(question, isRevealed) {
    var html = '<div class="quiz-options">';
    var selected = quizState.answers[question.id] || null;
    var keys = ['a', 'b', 'c', 'd'];
    keys.forEach(function (key) {
      if (!question.options[key]) return;
      var cls = 'quiz-option';
      if (selected === key) cls += ' selected';
      if (isRevealed) {
        if (key === question.answer) cls += ' correct';
        else if (selected === key) cls += ' incorrect';
        cls += ' revealed';
      }
      html += '<button class="' + cls + '" data-option="' + key + '"' + (isRevealed ? ' disabled' : '') + '>';
      html += '<span class="quiz-option-key">' + key.toUpperCase() + '</span>';
      html += '<span class="quiz-option-text">' + escapeHtml(question.options[key]) + '</span>';
      html += '</button>';
    });
    html += '</div>';
    if (!isRevealed) {
      html += '<button class="quiz-check-btn"' + (selected ? '' : ' disabled') + '>Check Answer</button>';
    }
    return html;
  }

  function renderCompleteQuestion(question, isRevealed) {
    var html = '<div class="quiz-complete-input-wrapper">';
    var userAnswer = quizState.answers[question.id] || '';
    var cls = 'quiz-complete-input';
    if (isRevealed) {
      var correct = checkCompleteAnswer(userAnswer, question);
      cls += correct ? ' correct' : ' incorrect';
    }
    html += '<input type="text" class="' + cls + '" id="quiz-complete-input" placeholder="Type your answer..." value="' + escapeHtml(userAnswer) + '"' + (isRevealed ? ' readonly' : '') + '>';
    if (isRevealed && !checkCompleteAnswer(userAnswer, question)) {
      html += '<div class="quiz-correct-answer">Correct answer: <code>' + escapeHtml(question.answer) + '</code></div>';
    }
    html += '</div>';
    if (!isRevealed) {
      html += '<button class="quiz-check-btn"' + (userAnswer.trim() ? '' : ' disabled') + '>Check Answer</button>';
    }
    return html;
  }

  function renderMatchQuestion(question, isRevealed) {
    var sel = quizState.matchSelections[question.id] || { left: null, pairs: [] };
    var pairedLeft = {};
    var pairedRight = {};
    var pairColors = ['pair-0', 'pair-1', 'pair-2', 'pair-3'];

    sel.pairs.forEach(function (p, i) {
      pairedLeft[p[0]] = i;
      pairedRight[p[1]] = i;
    });

    var html = '<div class="quiz-match-container">';
    html += '<div class="quiz-match-grid">';

    // Left column
    html += '<div class="quiz-match-left">';
    question.left.forEach(function (item, i) {
      var cls = 'quiz-match-item';
      if (sel.left === i) cls += ' active';
      if (pairedLeft[i] !== undefined) cls += ' paired ' + pairColors[pairedLeft[i] % 4];
      if (isRevealed) {
        var pairIdx = pairedLeft[i];
        if (pairIdx !== undefined) {
          var userPair = sel.pairs[pairIdx];
          cls += isMatchPairCorrect(userPair[0], userPair[1], question.pairs) ? ' correct' : ' incorrect';
        } else {
          cls += ' incorrect';
        }
        cls += ' revealed';
      }
      html += '<button class="' + cls + '" data-match-left="' + i + '"' + (isRevealed ? ' disabled' : '') + '>' + escapeHtml(item) + '</button>';
    });
    html += '</div>';

    // Right column
    html += '<div class="quiz-match-right">';
    question.right.forEach(function (item, i) {
      var cls = 'quiz-match-item';
      if (pairedRight[i] !== undefined) cls += ' paired ' + pairColors[pairedRight[i] % 4];
      if (isRevealed) {
        var pairIdx = pairedRight[i];
        if (pairIdx !== undefined) {
          var userPair = sel.pairs[pairIdx];
          cls += isMatchPairCorrect(userPair[0], userPair[1], question.pairs) ? ' correct' : ' incorrect';
        } else {
          cls += ' incorrect';
        }
        cls += ' revealed';
      }
      html += '<button class="' + cls + '" data-match-right="' + i + '"' + (isRevealed ? ' disabled' : '') + '>' + escapeHtml(item) + '</button>';
    });
    html += '</div>';

    html += '</div>'; // match-grid

    if (!isRevealed) {
      if (sel.pairs.length > 0) {
        html += '<button class="quiz-match-reset">Reset Pairs</button>';
      }
      html += '<button class="quiz-check-btn"' + (sel.pairs.length === question.left.length ? '' : ' disabled') + '>Check Answer</button>';
    }
    html += '</div>';
    return html;
  }

  function renderQuizScore(pack) {
    cleanupQuizHandlers();
    var app = document.getElementById('app');
    var total = pack.questions.length;
    var score = 0;
    pack.questions.forEach(function (q) {
      if (getAnswerCorrectness(q)) score++;
    });

    var pct = Math.round((score / total) * 100);
    var message = '';
    if (pct === 100) message = 'Perfect score!';
    else if (pct >= 80) message = 'Great job!';
    else if (pct >= 60) message = 'Good effort!';
    else if (pct >= 40) message = 'Keep practicing!';
    else message = 'Review the material and try again.';

    var html = '<div class="view-enter">';
    html += '<div class="quiz-score-card">';
    html += '<div class="quiz-score-header">' + escapeHtml(pack.topic) + '</div>';
    html += '<div class="quiz-score-number">' + score + '/' + total + '</div>';
    html += '<div class="quiz-score-pct">' + pct + '%</div>';
    html += '<div class="quiz-score-bar"><div class="quiz-score-fill" style="width:' + pct + '%"></div></div>';
    html += '<div class="quiz-score-message">' + escapeHtml(message) + '</div>';

    // Per-question breakdown
    html += '<div class="quiz-score-breakdown">';
    pack.questions.forEach(function (q, i) {
      var correct = getAnswerCorrectness(q);
      html += '<span class="quiz-score-dot ' + (correct ? 'correct' : 'incorrect') + '" title="Q' + (i + 1) + ': ' + (correct ? 'Correct' : 'Incorrect') + '">' + (i + 1) + '</span>';
    });
    html += '</div>';

    if (pack.related_drills && pack.related_drills.length) {
      html += '<div class="quiz-score-related">';
      html += '<div class="quiz-score-related-title">Practice with related drills:</div>';
      pack.related_drills.forEach(function (drill) {
        html += '<a class="quiz-related-link" href="#/drill/' + encodeURIComponent(drill) + '">' + escapeHtml(humanize(drill)) + '</a>';
      });
      html += '</div>';
    }

    html += '<div class="quiz-score-actions">';
    html += '<button class="quiz-restart-btn">Try Again</button>';
    html += '<a href="#/quizzes" class="quiz-back-btn">Back to Quizzes</a>';
    html += '</div>';
    html += '</div>';
    html += '</div>';

    app.innerHTML = html;

    app.addEventListener('click', function (e) {
      if (e.target.closest('.quiz-restart-btn')) {
        resetQuizState(pack.id);
        renderQuizSession(pack.id);
      }
    });
  }

  function cleanupQuizHandlers() {
    var app = document.getElementById('app');
    if (quizClickHandler) {
      app.removeEventListener('click', quizClickHandler);
      quizClickHandler = null;
    }
    if (quizInputHandler) {
      quizInputHandler = null;
    }
    if (quizKeyHandler) {
      quizKeyHandler = null;
    }
  }

  function bindQuizSessionEvents(pack) {
    cleanupQuizHandlers();
    var app = document.getElementById('app');
    var question = pack.questions[quizState.questionIndex];

    quizClickHandler = function (e) {
      // Diagnose option select
      var optBtn = e.target.closest('.quiz-option:not(.revealed)');
      if (optBtn && question.type === 'diagnose') {
        quizState.answers[question.id] = optBtn.dataset.option;
        renderQuizSession(pack.id);
        return;
      }

      // Check answer
      var checkBtn = e.target.closest('.quiz-check-btn:not([disabled])');
      if (checkBtn) {
        // For complete type, grab input value first
        if (question.type === 'complete') {
          var input = document.getElementById('quiz-complete-input');
          if (input) quizState.answers[question.id] = input.value;
        }
        quizState.revealed[question.id] = true;
        if (getAnswerCorrectness(question)) {
          quizState.score++;
        }
        renderQuizSession(pack.id);
        return;
      }

      // Next question
      var nextBtn = e.target.closest('.quiz-next-btn');
      if (nextBtn) {
        quizState.questionIndex++;
        renderQuizSession(pack.id);
        window.scrollTo(0, 0);
        return;
      }

      // Match left item
      var leftItem = e.target.closest('.quiz-match-item[data-match-left]:not(.revealed)');
      if (leftItem) {
        var leftIdx = parseInt(leftItem.dataset.matchLeft, 10);
        var sel = quizState.matchSelections[question.id] || { left: null, pairs: [] };
        // If already paired, unpair it
        var existingPairIdx = -1;
        sel.pairs.forEach(function (p, i) { if (p[0] === leftIdx) existingPairIdx = i; });
        if (existingPairIdx !== -1) {
          sel.pairs.splice(existingPairIdx, 1);
          sel.left = null;
          quizState.matchSelections[question.id] = sel;
          renderQuizSession(pack.id);
          return;
        }
        sel.left = leftIdx;
        quizState.matchSelections[question.id] = sel;
        renderQuizSession(pack.id);
        return;
      }

      // Match right item
      var rightItem = e.target.closest('.quiz-match-item[data-match-right]:not(.revealed)');
      if (rightItem) {
        var selR = quizState.matchSelections[question.id] || { left: null, pairs: [] };
        if (selR.left === null) return;
        var rightIdx = parseInt(rightItem.dataset.matchRight, 10);
        // If right already paired, remove old pair
        selR.pairs = selR.pairs.filter(function (p) { return p[1] !== rightIdx; });
        selR.pairs.push([selR.left, rightIdx]);
        selR.left = null;
        quizState.matchSelections[question.id] = selR;
        renderQuizSession(pack.id);
        return;
      }

      // Reset match pairs
      var resetBtn = e.target.closest('.quiz-match-reset');
      if (resetBtn) {
        quizState.matchSelections[question.id] = { left: null, pairs: [] };
        renderQuizSession(pack.id);
        return;
      }
    };

    app.addEventListener('click', quizClickHandler);

    // Complete input: enable check button on typing and Enter key
    if (question.type === 'complete') {
      var completeInput = document.getElementById('quiz-complete-input');
      if (completeInput && !quizState.revealed[question.id]) {
        completeInput.addEventListener('input', function () {
          quizState.answers[question.id] = completeInput.value;
          var checkBtnEl = app.querySelector('.quiz-check-btn');
          if (checkBtnEl) {
            checkBtnEl.disabled = !completeInput.value.trim();
          }
        });
        completeInput.addEventListener('keydown', function (e) {
          if (e.key === 'Enter' && completeInput.value.trim()) {
            quizState.answers[question.id] = completeInput.value;
            quizState.revealed[question.id] = true;
            if (getAnswerCorrectness(question)) {
              quizState.score++;
            }
            renderQuizSession(pack.id);
          }
        });
        completeInput.focus();
      }
    }
  }

  // --- Router ---
  function route() {
    var parsed = parseRoute();
    // Clean up quiz handlers when navigating away from quiz session
    if (parsed.view !== 'quiz') {
      cleanupQuizHandlers();
    }
    if (parsed.view === 'drill') {
      renderDrill(parsed.name);
    } else if (parsed.view === 'quizzes') {
      renderQuizCatalog(parsed.params);
    } else if (parsed.view === 'quiz') {
      renderQuizSession(parsed.packId);
    } else {
      renderCatalog(parsed.params);
    }
    window.scrollTo(0, 0);
  }

  // --- Init ---
  function init() {
    setupMarked();

    fetch('data.json')
      .then(function (res) {
        if (!res.ok) throw new Error('Failed to load data.json (HTTP ' + res.status + ')');
        return res.json();
      })
      .then(function (json) {
        data = json;

        // Update header count
        var countEl = document.getElementById('header-count');
        if (countEl) {
          var countText = data.meta.drill_count + ' drills';
          if (data.meta.question_count) {
            countText += ' · ' + data.meta.question_count + ' questions';
          }
          countEl.textContent = countText;
        }

        route();
        window.addEventListener('hashchange', route);
      })
      .catch(function (err) {
        document.getElementById('app').innerHTML =
          '<div class="no-results"><p class="no-results-title">Failed to load drill data</p>' +
          '<p>' + escapeHtml(err.message) + '</p><p style="margin-top:16px"><a href="data.json">Check data.json</a></p></div>';
      });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
