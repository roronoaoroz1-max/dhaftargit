/* Shared navigation and design chrome. No financial writes. */
(function(root){
"use strict";
const page=()=>location.pathname.split("/").pop()||"index.html";
const destinations=[["index.html","Home","home"],["amanah.html","Money","wallet"],["stock.html","Stock","box"]];
const more=[["admin.html#billStatusSection","Household bills"],["spending.html","Spending"],["admin.html#recurringPersonalPanel","Recurring payments"],["today.html","Today & reminders"],["statements.html","Statements"],["admin.html#adminMore","Settings & monthly setup"]];
const adds=[["spending.html#entryForm","Record expense"],["stock.html#items","Record stock purchase"],["stock.html#openBulkPurchase","Bulk purchase"],["admin.html#paymentCard","Household payment"],["amanah.html#personalSavingsForm","Add or withdraw savings"],["amanah.html#repaymentForm","Loan repayment"],["admin.html#recurringPersonalPanel","Recurring payment"],["amanah.html#assetCreateForm","Register personal asset"]];
const paths={home:"M3 10 12 3l9 7v10h-6v-6H9v6H3z",wallet:"M3 5h16v14H3z M15 10h6v5h-6z",box:"M3 7l9-4 9 4v10l-9 4-9-4z M3 7l9 4 9-4 M12 11v10",plus:"M12 5v14 M5 12h14",menu:"M4 6h16 M4 12h16 M4 18h16"};
const el=(tag,t,cls)=>{const n=document.createElement(tag);if(t!==undefined)n.textContent=t;if(cls)n.className=cls;return n;};
function icon(name){const svg=document.createElementNS("http://www.w3.org/2000/svg","svg");svg.setAttribute("viewBox","0 0 24 24");svg.setAttribute("aria-hidden","true");svg.setAttribute("fill","none");svg.setAttribute("stroke","currentColor");svg.setAttribute("stroke-width","1.7");svg.setAttribute("stroke-linecap","round");svg.setAttribute("stroke-linejoin","round");const p=document.createElementNS(svg.namespaceURI,"path");p.setAttribute("d",paths[name]);svg.append(p);return svg;}
function current(href,p=page()){return href.split("#")[0]===p;}
let nav,dialog,authorized=false;
function revealTarget(){
 const id=location.hash.slice(1);if(!/^[A-Za-z][A-Za-z0-9_-]*$/.test(id))return;
 const target=document.getElementById(id);if(!target)return;
 for(let n=target;n;n=n.parentElement){if(n.tagName==="DETAILS")n.open=true;}
 if(target.getClientRects().length){target.scrollIntoView({block:"start",behavior:"auto"});}
}
function routeLink(href,label){const a=el("a",label,"dx-menu-link");a.href=href;a.addEventListener("click",()=>{if(dialog?.open)dialog.close();if(current(href)&&href.includes("#"))setTimeout(revealTarget,0);});return a;}
function openMenu(title,rows){if(!authorized)return;dialog.replaceChildren();const h=el("div",undefined,"dx-menu-head");const heading=el("h2",title);heading.id="dxMenuTitle";const close=el("button","Close","dx-menu-link");close.type="button";close.addEventListener("click",()=>dialog.close());h.append(heading,close);dialog.append(h);for(const [href,label] of rows)dialog.append(routeLink(href,label));dialog.showModal();}
function navItem(href,label,glyph){const a=el("a",undefined,"dx-nav-item");a.href=href;a.append(icon(glyph),el("span",label));if(current(href))a.setAttribute("aria-current","page");return a;}
function action(label,glyph,fn){const b=el("button",undefined,"dx-nav-item");b.type="button";b.append(icon(glyph),el("span",label));b.addEventListener("click",fn);return b;}
function setAuthorized(value){authorized=value;if(!nav)return;nav.hidden=!value;document.documentElement.classList.toggle("dx-nav-active",value);if(!value&&dialog.open)dialog.close();if(value)revealTarget();}
function init(){
 if(nav)return;
 nav=el("nav",undefined,"dx-nav");nav.setAttribute("aria-label","Dhaftar main navigation");nav.hidden=true;
 nav.append(navItem(...destinations[0]),navItem(...destinations[1]),action("Add","plus",()=>openMenu("Quick add",adds)),navItem(...destinations[2]),action("More","menu",()=>openMenu("More",more)));
 dialog=el("dialog",undefined,"dx-menu");dialog.setAttribute("aria-labelledby","dxMenuTitle");document.body.append(nav,dialog);
 root.addEventListener("hashchange",revealTarget);
 root.addEventListener("dhaftar:notification-access",e=>setAuthorized(e.detail===true));
 // Handles either script order without a second authentication or database request.
 setAuthorized(root.DhaftarNotifications?.hasAccess?.()===true);
}
root.DhaftarUX=Object.freeze({init,current});
})(globalThis);
