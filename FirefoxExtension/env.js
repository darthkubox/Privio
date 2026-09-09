// Wariant dla Firefoksa - ta wtyczka jest osobnym pakietem (MV2, API `browser.proxy`
// + `webRequest`), więc zawsze raportujemy „Firefox". Panel statusu w Privio pokaże
// dzięki temu właściwą przeglądarkę.
const PrivioEnv = {
  browser() { return "Firefox"; }
};
if (typeof globalThis !== "undefined") globalThis.PrivioEnv = PrivioEnv;
