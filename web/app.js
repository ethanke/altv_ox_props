(() => {
    const resourceName = typeof GetParentResourceName === 'function'
        ? GetParentResourceName()
        : 'ox_props';

    /**
     * Posts a NUI callback to the FiveM client.
     * @param {string} name
     * @param {object} [data]
     * @returns {Promise<any>}
     */
    async function nui(name, data = {}) {
        try {
            const response = await fetch(`https://${resourceName}/${name}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(data),
            });
            return await response.json();
        } catch {
            return null;
        }
    }

    window.OxPropsNui = { resourceName, nui };

    window.addEventListener('message', (event) => {
        const { action, data } = event.data || {};
        if (!action) return;

        if (action === 'catalog:open') {
            window.OxPropsCatalog?.open(data);
            return;
        }

        if (action === 'catalog:close') {
            window.OxPropsCatalog?.close();
            return;
        }

        if (action === 'catalog:forge') {
            window.OxPropsCatalog?.onForge(data);
        }
    });
})();
