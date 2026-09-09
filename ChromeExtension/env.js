// Wykrywa przeglądarkę-gospodarza (Chromium). Ta sama wtyczka MV3 działa w
// Chrome/Edge/Brave/Opera/Vivaldi; raportujemy właściwą nazwę, żeby panel statusu
// w Privio pokazał odpowiednią przeglądarkę. Detekcja tylko z User-Agent, żeby była
// spójna między service workerem a stronami (Brave nie ujawnia się w UA → „Chrome").
const PrivioEnv = {
  browser() {
    let ua = "";
    try { ua = navigator.userAgent || ""; } catch (_) {}
    if (/\bEdg(?:e|A|iOS)?\//.test(ua)) return "Edge";
    if (/\bOPR\/|\bOPiOS\//.test(ua)) return "Opera";
    if (/\bVivaldi\//.test(ua)) return "Vivaldi";
    return "Chrome";
  }
};
if (typeof globalThis !== "undefined") globalThis.PrivioEnv = PrivioEnv;
