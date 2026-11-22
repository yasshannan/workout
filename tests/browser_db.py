"""Helpers for the data tests: a local web server for the project, and reading /
writing the phone app's IndexedDB in the browser exactly as it is stored."""
import functools, http.server, json, pathlib, shutil, socketserver, threading

ROOT = pathlib.Path(__file__).resolve().parent.parent          # the project folder
DB_NAME = "workout-tracker"


def start_server():
    """Serve the project folder on a free port. Returns the base address."""
    class Quiet(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass
    handler = functools.partial(Quiet, directory=str(ROOT))
    server = socketserver.TCPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return f"http://127.0.0.1:{server.server_address[1]}/"


def launch(playwright):
    chrome = shutil.which("google-chrome") or shutil.which("chrome")
    return playwright.chromium.launch(executable_path=chrome, headless=True) if chrome else playwright.chromium.launch(headless=True)


DUMP_JS = """async (name) => {
  const db = await new Promise((ok, fail) => { const r = indexedDB.open(name); r.onsuccess = () => ok(r.result); r.onerror = () => fail(r.error); });
  const out = { dbVersion: db.version, stores: {} };
  for (const store of db.objectStoreNames) {
    const s = db.transaction(store, 'readonly').objectStore(store);
    const records = await new Promise((ok) => { const r = s.getAll(); r.onsuccess = () => ok(r.result); });
    out.stores[store] = { keyPath: s.keyPath, indexes: [...s.indexNames].map((i) => ({ name: i, keyPath: s.index(i).keyPath })), records };
  }
  db.close();
  return out;
}"""

WRITE_JS = """async ([name, dump]) => {
  const db = await new Promise((ok, fail) => {
    const r = indexedDB.open(name, dump.dbVersion);
    r.onupgradeneeded = () => {
      for (const [store, info] of Object.entries(dump.stores)) {
        const s = r.result.createObjectStore(store, { keyPath: info.keyPath });
        for (const index of info.indexes) s.createIndex(index.name, index.keyPath);
      }
    };
    r.onsuccess = () => ok(r.result); r.onerror = () => fail(r.error);
  });
  for (const [store, info] of Object.entries(dump.stores)) {
    await new Promise((ok, fail) => {
      const tx = db.transaction(store, 'readwrite');
      info.records.forEach((record) => tx.objectStore(store).put(record));
      tx.oncomplete = ok; tx.onerror = () => fail(tx.error);
    });
  }
  db.close();
}"""


def dump(page):
    return page.evaluate(DUMP_JS, DB_NAME)


def write(page, data):
    page.evaluate(WRITE_JS, [DB_NAME, data])
