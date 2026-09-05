(() => {
    const DB_NAME = 'ox_props_preview';
    const DB_VERSION = 1;
    const STORE = 'assets';

    /** @type {{
     *   enabled: boolean,
     *   provider: string,
     *   cacheMaxEntries: number,
     *   lazyRootMargin: string,
     *   forgeObjectUrl?: string,
     *   thumbnailUrl?: string,
     *   meshUrl?: string,
     * }} */
    let config = {
        enabled: false,
        provider: 'none',
        cacheMaxEntries: 128,
        lazyRootMargin: '200px',
    };

    /** @type {IntersectionObserver | null} */
    let observer = null;

    /** @type {IDBDatabase | null} */
    let db = null;

    /** @type {Map<string, string>} memory blob URLs keyed by cache key */
    const memoryUrls = new Map();

    /**
     * Minimal viewport stub for future glTF/Three.js rendering.
     * Does not load Three.js — paints a placeholder until a mesh provider is wired.
     */
    class MeshViewport {
        /** @param {HTMLElement} host */
        constructor(host) {
            this.host = host;
            this.canvas = document.createElement('canvas');
            this.canvas.width = 128;
            this.canvas.height = 72;
            this.ctx = this.canvas.getContext('2d');
            this.model = null;
            this.disposed = false;
        }

        /** @param {string} model */
        setModel(model) {
            this.model = model;
            this.paintStub();
        }

        /**
         * Future: load ArrayBuffer / glTF URL into a Three.js scene.
         * @param {string} _meshUrl
         * @returns {Promise<void>}
         */
        async loadMesh(_meshUrl) {
            this.paintStub();
        }

        paintStub() {
            if (this.disposed || !this.ctx) return;

            const { canvas, ctx } = this;
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            ctx.fillStyle = '#12151c';
            ctx.fillRect(0, 0, canvas.width, canvas.height);
            ctx.strokeStyle = '#2a3140';
            ctx.strokeRect(0.5, 0.5, canvas.width - 1, canvas.height - 1);
            ctx.fillStyle = '#5b6b84';
            ctx.font = '10px ui-monospace, Consolas, monospace';
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';
            ctx.fillText('mesh', canvas.width / 2, canvas.height / 2);
        }

        mount() {
            this.host.replaceChildren(this.canvas);
            this.paintStub();
        }

        dispose() {
            this.disposed = true;
            this.ctx = null;
            this.canvas.remove();
        }
    }

    function formatUrl(template, model) {
        if (!template) return null;
        try {
            return template.replace('%s', encodeURIComponent(model));
        } catch {
            return null;
        }
    }

    function openDb() {
        if (db) return Promise.resolve(db);

        return new Promise((resolve, reject) => {
            const req = indexedDB.open(DB_NAME, DB_VERSION);

            req.onupgradeneeded = () => {
                const database = req.result;
                if (!database.objectStoreNames.contains(STORE)) {
                    const store = database.createObjectStore(STORE, { keyPath: 'key' });
                    store.createIndex('lastAccess', 'lastAccess');
                }
            };

            req.onsuccess = () => {
                db = req.result;
                resolve(db);
            };

            req.onerror = () => reject(req.error);
        });
    }

    /**
     * @param {string} key
     * @returns {Promise<{ key: string, blob: Blob, lastAccess: number } | null>}
     */
    async function idbGet(key) {
        try {
            const database = await openDb();
            return await new Promise((resolve, reject) => {
                const tx = database.transaction(STORE, 'readonly');
                const req = tx.objectStore(STORE).get(key);
                req.onsuccess = () => resolve(req.result || null);
                req.onerror = () => reject(req.error);
            });
        } catch {
            return null;
        }
    }

    /**
     * @param {{ key: string, blob: Blob, lastAccess: number }} entry
     */
    async function idbPut(entry) {
        try {
            const database = await openDb();
            await new Promise((resolve, reject) => {
                const tx = database.transaction(STORE, 'readwrite');
                tx.objectStore(STORE).put(entry);
                tx.oncomplete = () => resolve();
                tx.onerror = () => reject(tx.error);
            });
            await trimLru();
        } catch {
            // Cache is best-effort.
        }
    }

    async function trimLru() {
        const max = config.cacheMaxEntries || 128;
        if (max <= 0) return;

        try {
            const database = await openDb();
            const entries = await new Promise((resolve, reject) => {
                const tx = database.transaction(STORE, 'readonly');
                const req = tx.objectStore(STORE).index('lastAccess').getAll();
                req.onsuccess = () => resolve(req.result || []);
                req.onerror = () => reject(req.error);
            });

            if (entries.length <= max) return;

            entries.sort((a, b) => a.lastAccess - b.lastAccess);
            const excess = entries.length - max;
            const toDelete = entries.slice(0, excess);

            await new Promise((resolve, reject) => {
                const tx = database.transaction(STORE, 'readwrite');
                const store = tx.objectStore(STORE);
                for (let i = 0; i < toDelete.length; i++) {
                    store.delete(toDelete[i].key);
                }
                tx.oncomplete = () => resolve();
                tx.onerror = () => reject(tx.error);
            });
        } catch {
            // ignore
        }
    }

    /**
     * Fetches a URL and caches the blob in IndexedDB (LRU by lastAccess).
     * @param {string} url
     * @returns {Promise<string | null>} object URL
     */
    async function fetchCached(url) {
        if (memoryUrls.has(url)) {
            return memoryUrls.get(url);
        }

        const cached = await idbGet(url);
        if (cached?.blob) {
            await idbPut({ key: url, blob: cached.blob, lastAccess: Date.now() });
            const objectUrl = URL.createObjectURL(cached.blob);
            memoryUrls.set(url, objectUrl);
            return objectUrl;
        }

        try {
            const response = await fetch(url);
            if (!response.ok) return null;

            const blob = await response.blob();
            await idbPut({ key: url, blob, lastAccess: Date.now() });
            const objectUrl = URL.createObjectURL(blob);
            memoryUrls.set(url, objectUrl);
            return objectUrl;
        } catch {
            return null;
        }
    }

    /**
     * Resolves preview URLs via NUI callback (authoritative) with local fallback.
     * @param {string} model
     */
    async function resolvePreview(model) {
        const fromClient = await window.OxPropsNui?.nui('catalog:preview', { model });
        if (fromClient && typeof fromClient === 'object') {
            return fromClient;
        }

        return {
            thumbnailUrl: formatUrl(config.thumbnailUrl, model),
            meshUrl: formatUrl(config.meshUrl, model),
            forgeUrl: formatUrl(config.forgeObjectUrl || 'https://forge.plebmasters.de/objects/%s', model),
        };
    }

    /**
     * @param {HTMLElement} el
     */
    async function loadInto(el) {
        if (!config.enabled || config.provider === 'none') return;

        const model = el.dataset.model;
        if (!model || el.dataset.loaded === '1') return;

        el.dataset.loaded = '1';

        const resolved = await resolvePreview(model);
        if (el.dataset.model !== model) return;

        if (resolved.thumbnailUrl) {
            const objectUrl = await fetchCached(resolved.thumbnailUrl);
            if (objectUrl && el.dataset.model === model) {
                const img = document.createElement('img');
                img.alt = model;
                img.loading = 'lazy';
                img.src = objectUrl;
                el.replaceChildren(img);
                return;
            }
        }

        if (resolved.meshUrl) {
            const viewport = new MeshViewport(el);
            viewport.mount();
            viewport.setModel(model);
            await viewport.loadMesh(resolved.meshUrl);
            el._meshViewport = viewport;
            return;
        }

        // Provider enabled but no URL templates — keep stub.
        el.dataset.loaded = '0';
    }

    function ensureObserver() {
        if (observer) {
            observer.disconnect();
            observer = null;
        }

        observer = new IntersectionObserver((entries) => {
            for (let i = 0; i < entries.length; i++) {
                const entry = entries[i];
                if (!entry.isIntersecting) continue;
                loadInto(/** @type {HTMLElement} */ (entry.target));
            }
        }, {
            root: document.getElementById('grid-viewport'),
            rootMargin: config.lazyRootMargin || '200px',
            threshold: 0.01,
        });
    }

    function configure(next) {
        config = {
            enabled: next?.enabled === true,
            provider: next?.provider || 'none',
            cacheMaxEntries: next?.cacheMaxEntries || 128,
            lazyRootMargin: next?.lazyRootMargin || '200px',
            forgeObjectUrl: next?.forgeObjectUrl,
            thumbnailUrl: next?.thumbnailUrl,
            meshUrl: next?.meshUrl,
        };
        ensureObserver();
    }

    /** @param {HTMLElement | null | undefined} el */
    function observe(el) {
        if (!el || !observer) return;
        if (!config.enabled || config.provider === 'none') return;
        el.dataset.loaded = '0';
        observer.observe(el);
    }

    /** @param {HTMLElement | null | undefined} el */
    function unobserve(el) {
        if (!el || !observer) return;
        observer.unobserve(el);
        if (el._meshViewport) {
            el._meshViewport.dispose();
            el._meshViewport = null;
        }
    }

    function clear() {
        if (observer) {
            observer.disconnect();
            observer = null;
        }

        for (const url of memoryUrls.values()) {
            URL.revokeObjectURL(url);
        }
        memoryUrls.clear();
    }

    window.OxPropsPreview = {
        MeshViewport,
        configure,
        observe,
        unobserve,
        clear,
    };
})();
