/* UI-only module sections. Existing nodes, listeners and form values are retained. */
(function(root){
"use strict";
const configs={
 "amanah.html":{root:"amanahApp",tabs:[
 ["overview","Overview",[".overview-section"]],
 ["personal","My money",['section[aria-labelledby="personalSavingsTitle"]']],
 ["assets","Assets",['section[aria-labelledby="personalAssetsTitle"]']],
 ["loans","Loans & accounts",['section[aria-labelledby="personLoanTitle"]','section[aria-labelledby="borrowerLedgerTitle"]',".data-stack"]],
 ["manage","Manage",[".management-heading",".management-grid"]]]},
 "admin.html":{root:"adminApp",tabs:[
 ["overview","Overview",["#adminHome"]],
 ["bills","Bills & setup",["#billStatusSection","#adminMore","#rentWork"]],
 ["payment","Payment",["#paymentCard"]],
 ["history","History & closing",["#historyWork","#closingWork"]],
 ["amanah","Amanah",['section[aria-labelledby="amanahTitle"]']]]},
 "stock.html":{root:"stockApp",tabs:[
 ["items","Items",[".toolbar","#items"]],
 ["shopping","Shopping",[".shopping-card"]],
 ["new","Add item",["#newItemPanel"]]]},
 "spending.html":{root:"app",tabs:[
 ["entry","Add spending",[".entry-card"]],
 ["insights","Insights",[".insights"]],
 ["history","History",[".history-card"]]]}
};
let groups=[],bar=null,selected=null,host=null;
function tabFor(target){return groups.find(g=>g.nodes.some(n=>n===target||n.contains(target)))?.key||null;}
function select(key){if(!groups.some(g=>g.key===key))return false;selected=key;for(const g of groups){const on=g.key===key;g.button.setAttribute("aria-pressed",String(on));for(const n of g.nodes)n.classList.toggle("dx-section-hidden",!on);}return true;}
function reveal(target){const key=tabFor(target);if(!key)return false;select(key);return true;}
function revealHash(){const id=location.hash.slice(1);if(!/^[A-Za-z][A-Za-z0-9_-]*$/.test(id))return;const n=document.getElementById(id);if(n&&reveal(n)){for(let p=n;p&&p!==host;p=p.parentElement)if(p.tagName==="DETAILS")p.open=true;if(n.getClientRects().length)n.scrollIntoView({block:"start"});}}
function init(){if(bar)return;const config=configs[location.pathname.split("/").pop()];if(!config)return;host=document.getElementById(config.root);if(!host)return;
 const found=config.tabs.map(([key,label,selectors])=>({key,label,nodes:selectors.flatMap(s=>Array.from(host.querySelectorAll(s)))}));
 // Fail open if markup changes, rather than hiding a section without a working tab.
 if(found.some(g=>!g.nodes.length)||new Set(found.flatMap(g=>g.nodes)).size!==found.flatMap(g=>g.nodes).length)return;
 groups=found;bar=document.createElement("nav");bar.className="dx-section-nav";bar.setAttribute("aria-label","Module sections");
 for(const g of groups){const b=document.createElement("button");b.type="button";b.textContent=g.label;b.setAttribute("aria-pressed","false");b.addEventListener("click",()=>select(g.key));g.button=b;bar.append(b);}
 const first=groups[0].nodes[0];first.parentNode.insertBefore(bar,first);
 select(groups[0].key);root.addEventListener("hashchange",revealHash);
 root.addEventListener("dhaftar:notification-access",e=>{if(e.detail===true&&location.hash&&!hashHandled){hashHandled=true;revealHash();}else if(!e.detail)hashHandled=false;});
 revealHash();
}
let hashHandled=false;
root.DhaftarSections=Object.freeze({init,reveal,select,configs});
})(globalThis);
