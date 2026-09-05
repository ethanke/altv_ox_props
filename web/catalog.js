(() => {
    const ROW_HEIGHT = 108;
    const GAP = 10;
    const OVERSCAN = 2;
    const SEARCH_DEBOUNCE_MS = 120;

    const els = {
        app: document.getElementById('app'),
        title: document.getElementById('catalog-title'),
        workingSet: document.getElementById('working-set'),
        categoryList: document.getElementById('category-list'),
        search: document.getElementById('search'),
        resultCount: document.getElementById('result-count'),
        gridViewport: document.getElementById('grid-viewport'),
        gridSpacer: document.getElementById('grid-spacer'),
        grid: document.getElementById('grid'),
        emptyState: document.getElementById('empty-state'),
        selectionBar: document.getElementById('selection-bar'),
        selectedModel: document.getElementById('selected-model'),
        selectedCategory: document.getElementById('selected-category'),
        btnPlace: document.getElementById('btn-place'),
        btnCopy: document.getElementById('btn-copy'),
        btnForge: document.getElementById('btn-forge'),
        btnCustom: document.getElementById('btn-custom'),
        btnClose: document.getElementById('btn-close'),
    };

    /** @type {{ id: string, label: string, count: number }[]} */
    let categories = [];
    /** @type {{ model: string, categoryId: string, categoryLabel: string }[]} */
    let allModels = [];
    /** @type {{ model: string, categoryId: string, categoryLabel: string }[]} */
    let filtered = [];
    /** @type {Record<string, string>} */
    let locale = {};
    let activeCategory = 'all';
    let searchQuery = '';
    let selectedIndex = -1;
    let open = false;
    let cols = 4;
    let searchTimer = null;

    function getCols() {
        const width = els.gridViewport.clientWidth || 800;
        if (width < 700) return 2;
        if (width < 1000) return 3;
        return 4;
    }

    function nui(name, data) {
        return window.OxPropsNui?.nui(name, data);
    }

    function applyLocale(loc) {
        locale = loc || {};
        els.title.textContent = locale.title || 'Prop Catalog';
        els.search.placeholder = locale.search || 'Search models…';
        els.btnPlace.textContent = locale.place || 'Place';
        els.btnCopy.textContent = locale.copy || 'Copy';
        els.btnForge.textContent = locale.forge || 'Forge';
        els.btnCustom.textContent = locale.custom || 'Custom';
        els.btnClose.textContent = locale.close || 'Close';
        els.emptyState.textContent = locale.empty || 'No models found.';
    }

    function renderCategories() {
        const frag = document.createDocumentFragment();

        const allBtn = document.createElement('button');
        allBtn.type = 'button';
        allBtn.className = `category-item${activeCategory === 'all' ? ' active' : ''}`;
        allBtn.dataset.id = 'all';
        allBtn.innerHTML = `<span>${locale.all || 'All'}</span><span class="category-count">${allModels.length}</span>`;
        frag.appendChild(allBtn);

        for (let i = 0; i < categories.length; i++) {
            const cat = categories[i];
            const btn = document.createElement('button');
            btn.type = 'button';
            btn.className = `category-item${activeCategory === cat.id ? ' active' : ''}`;
            btn.dataset.id = cat.id;
            btn.innerHTML = `<span>${cat.label}</span><span class="category-count">${cat.count}</span>`;
            frag.appendChild(btn);
        }

        els.categoryList.replaceChildren(frag);
    }

    function rebuildFilter() {
        const q = searchQuery.trim().toLowerCase();
        const out = [];

        for (let i = 0; i < allModels.length; i++) {
            const item = allModels[i];
            if (activeCategory !== 'all' && item.categoryId !== activeCategory) continue;
            if (q && !item.model.includes(q)) continue;
            out.push(item);
        }

        filtered = out;

        if (selectedIndex >= filtered.length) {
            selectedIndex = filtered.length > 0 ? 0 : -1;
        } else if (selectedIndex < 0 && filtered.length > 0) {
            selectedIndex = 0;
        }

        const template = locale.results || '%s results';
        els.resultCount.textContent = template.includes('%s')
            ? template.replace('%s', String(filtered.length))
            : `${filtered.length}`;

        const empty = filtered.length === 0;
        els.emptyState.classList.toggle('hidden', !empty);
        els.grid.classList.toggle('hidden', empty);

        updateSelectionBar();
        renderVirtual();
    }

    function updateSelectionBar() {
        const item = selectedIndex >= 0 ? filtered[selectedIndex] : null;
        els.selectionBar.classList.toggle('hidden', !item);

        if (!item) return;

        els.selectedModel.textContent = item.model;
        els.selectedCategory.textContent = item.categoryLabel;
    }

    function cardKey(index) {
        return `card-${index}`;
    }

    function ensureCard(index, item) {
        let card = els.grid.querySelector(`[data-index="${index}"]`);

        if (!card) {
            card = document.createElement('button');
            card.type = 'button';
            card.className = 'card';
            card.dataset.index = String(index);
            card.setAttribute('role', 'listitem');

            const preview = document.createElement('div');
            preview.className = 'card-preview';
            preview.dataset.model = item.model;

            const stub = document.createElement('span');
            stub.className = 'preview-stub';
            stub.textContent = 'prop';
            preview.appendChild(stub);

            const label = document.createElement('div');
            label.className = 'card-label';

            card.appendChild(preview);
            card.appendChild(label);
            els.grid.appendChild(card);

            window.OxPropsPreview?.observe(preview);
        }

        const label = card.querySelector('.card-label');
        if (label) label.textContent = item.model;

        const preview = card.querySelector('.card-preview');
        if (preview && preview.dataset.model !== item.model) {
            preview.dataset.model = item.model;
            preview.replaceChildren();
            const stub = document.createElement('span');
            stub.className = 'preview-stub';
            stub.textContent = 'prop';
            preview.appendChild(stub);
            window.OxPropsPreview?.observe(preview);
        }

        card.classList.toggle('selected', index === selectedIndex);
        card.title = item.model;

        return card;
    }

    function renderVirtual() {
        cols = getCols();
        document.documentElement.style.setProperty('--cols', String(cols));

        const total = filtered.length;
        const rowCount = Math.ceil(total / cols) || 0;
        const totalHeight = rowCount > 0 ? rowCount * ROW_HEIGHT + Math.max(0, rowCount - 1) * GAP : 0;

        els.gridSpacer.style.height = `${totalHeight}px`;

        if (total === 0) {
            els.grid.replaceChildren();
            return;
        }

        const scrollTop = els.gridViewport.scrollTop;
        const viewHeight = els.gridViewport.clientHeight;
        const rowStride = ROW_HEIGHT + GAP;

        let firstRow = Math.floor(scrollTop / rowStride) - OVERSCAN;
        let lastRow = Math.ceil((scrollTop + viewHeight) / rowStride) + OVERSCAN;
        firstRow = Math.max(0, firstRow);
        lastRow = Math.min(rowCount - 1, lastRow);

        const firstIndex = firstRow * cols;
        const lastIndex = Math.min(total - 1, (lastRow + 1) * cols - 1);

        const keep = new Set();
        for (let i = firstIndex; i <= lastIndex; i++) {
            keep.add(cardKey(i));
            ensureCard(i, filtered[i]);
        }

        const children = [...els.grid.children];
        for (let i = 0; i < children.length; i++) {
            const child = children[i];
            const idx = Number(child.dataset.index);
            if (!keep.has(cardKey(idx)) || idx >= total) {
                window.OxPropsPreview?.unobserve(child.querySelector('.card-preview'));
                child.remove();
            }
        }

        els.grid.style.transform = `translateY(${firstRow * rowStride}px)`;
    }

    function selectIndex(index) {
        if (index < 0 || index >= filtered.length) return;
        selectedIndex = index;
        updateSelectionBar();
        renderVirtual();
    }

    function placeSelected() {
        const item = filtered[selectedIndex];
        if (!item) return;
        nui('catalog:place', { model: item.model });
    }

    function openCatalog(data) {
        categories = data?.categories || [];
        allModels = data?.models || [];
        activeCategory = 'all';
        searchQuery = '';
        selectedIndex = allModels.length > 0 ? 0 : -1;
        els.search.value = '';

        applyLocale(data?.locale);
        els.workingSet.textContent = data?.workingSet || '';

        window.OxPropsPreview?.configure(data?.preview || {});

        open = true;
        els.app.classList.remove('hidden');
        els.app.setAttribute('aria-hidden', 'false');

        renderCategories();
        rebuildFilter();
        els.gridViewport.scrollTop = 0;
        els.search.focus();
    }

    function closeCatalog(notifyClient) {
        if (!open) return;
        open = false;
        els.app.classList.add('hidden');
        els.app.setAttribute('aria-hidden', 'true');
        window.OxPropsPreview?.clear();

        if (notifyClient) {
            nui('catalog:close');
        }
    }

    els.categoryList.addEventListener('click', (event) => {
        const btn = event.target.closest('.category-item');
        if (!btn) return;

        activeCategory = btn.dataset.id || 'all';
        selectedIndex = 0;
        renderCategories();
        rebuildFilter();
        els.gridViewport.scrollTop = 0;
    });

    els.search.addEventListener('input', () => {
        clearTimeout(searchTimer);
        searchTimer = setTimeout(() => {
            searchQuery = els.search.value || '';
            selectedIndex = 0;
            rebuildFilter();
            els.gridViewport.scrollTop = 0;
        }, SEARCH_DEBOUNCE_MS);
    });

    els.gridViewport.addEventListener('scroll', () => {
        renderVirtual();
    }, { passive: true });

    els.grid.addEventListener('click', (event) => {
        const card = event.target.closest('.card');
        if (!card) return;

        const index = Number(card.dataset.index);
        if (Number.isNaN(index)) return;

        if (index === selectedIndex && event.detail === 2) {
            placeSelected();
            return;
        }

        selectIndex(index);
    });

    els.btnPlace.addEventListener('click', placeSelected);

    els.btnCopy.addEventListener('click', () => {
        const item = filtered[selectedIndex];
        if (!item) return;
        nui('catalog:copy', { model: item.model });
    });

    els.btnForge.addEventListener('click', () => {
        const item = filtered[selectedIndex];
        if (!item) return;
        nui('catalog:forge', { model: item.model });
    });

    els.btnCustom.addEventListener('click', () => {
        nui('catalog:custom');
    });

    els.btnClose.addEventListener('click', () => {
        closeCatalog(true);
    });

    window.addEventListener('keydown', (event) => {
        if (!open) return;

        if (event.key === 'Escape') {
            event.preventDefault();
            closeCatalog(true);
            return;
        }

        if (event.key === 'Enter' && document.activeElement !== els.search) {
            event.preventDefault();
            placeSelected();
            return;
        }

        if (event.key === 'ArrowRight' || event.key === 'ArrowLeft' || event.key === 'ArrowDown' || event.key === 'ArrowUp') {
            if (document.activeElement === els.search) return;
            event.preventDefault();

            let next = selectedIndex;
            if (event.key === 'ArrowRight') next += 1;
            if (event.key === 'ArrowLeft') next -= 1;
            if (event.key === 'ArrowDown') next += cols;
            if (event.key === 'ArrowUp') next -= cols;

            next = Math.max(0, Math.min(filtered.length - 1, next));
            selectIndex(next);

            const row = Math.floor(next / cols);
            const rowTop = row * (ROW_HEIGHT + GAP);
            const rowBottom = rowTop + ROW_HEIGHT;
            const viewTop = els.gridViewport.scrollTop;
            const viewBottom = viewTop + els.gridViewport.clientHeight;

            if (rowTop < viewTop) {
                els.gridViewport.scrollTop = rowTop;
            } else if (rowBottom > viewBottom) {
                els.gridViewport.scrollTop = rowBottom - els.gridViewport.clientHeight;
            }
        }
    });

    window.addEventListener('resize', () => {
        if (!open) return;
        renderVirtual();
    });

    window.OxPropsCatalog = {
        open: openCatalog,
        close: () => closeCatalog(false),
        onForge(data) {
            if (data?.url) {
                console.info('[ox_props] Forge URL:', data.url, data.model || '');
            }
        },
    };
})();
