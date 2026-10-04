export function createBus() {
  const subs = new Map();
  return {
    subscribe(instanceId, fn) {
      if (!subs.has(instanceId)) subs.set(instanceId, new Set());
      subs.get(instanceId).add(fn);
      return () => {
        subs.get(instanceId)?.delete(fn);
        if (!subs.get(instanceId)?.size) subs.delete(instanceId);
      };
    },
    publish(instanceId, event) {
      for (const fn of subs.get(instanceId) || []) {
        try { fn(event); } catch {}
      }
    },
    size: () => [...subs.values()].reduce((n, set) => n + set.size, 0),
  };
}
