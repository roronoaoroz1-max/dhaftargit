/* Private home dashboard; read-only existing RPCs. */
(function(root){
"use strict";
let client,epoch=0,active=false,loading=false;
const el=id=>document.getElementById(id);
const money=(n,c)=>Number.isFinite(Number(n))&&n!==null?c+" "+Number(n).toLocaleString("en-GB",{minimumFractionDigits:2,maximumFractionDigits:2}):"Unavailable";
function clear(){++epoch;active=false;loading=false;el("dxDashboard").hidden=true;for(const id of ["dxWorth","dxSavings","dxDebt","dxUsd"])el(id).textContent="—";el("dxAttention").replaceChildren();}
function renderTotals(rows){const m=rows.find(r=>r.currency==="MVR"),u=rows.find(r=>r.currency==="USD");el("dxWorth").textContent=money(m?.net_worth,"MVR");el("dxSavings").textContent=money(m?.savings,"MVR");el("dxDebt").textContent=money(m?.total_liabilities,"MVR");el("dxUsd").textContent=money(u?.net_worth,"USD");}
function renderAttention(feed){const box=el("dxAttention");box.replaceChildren();const list=feed.notifications.filter(n=>!n.snoozed);for(const n of list.slice(0,5)){const a=document.createElement("a");a.href="today.html";a.className="dx-attention-row";const t=document.createElement("strong");t.textContent=n.title;const d=document.createElement("small");d.textContent=root.DhaftarNotifications.urgency(n)+(n.due_date?" · "+n.due_date:"");a.append(t,d);box.append(a);}if(!list.length)box.textContent="No active reminders.";el("dxReminderCount").textContent=String(list.length)+" active";}
async function refresh(){if(!active||loading)return;loading=true;const t=++epoch;try{const [worth,notices]=await Promise.all([client.rpc("dhaftar_net_worth_v5"),client.rpc("dhaftar_notifications_v6")]);if(t!==epoch||!active)return;if(worth.error||notices.error||!Array.isArray(worth.data)||!Array.isArray(notices.data?.notifications))throw Error("Dashboard unavailable");renderTotals(worth.data);renderAttention(notices.data);el("dxDashboardStatus").textContent="Latest recorded balances · currencies shown separately";}catch(e){if(t===epoch){for(const id of ["dxWorth","dxSavings","dxDebt","dxUsd"])el(id).textContent="—";el("dxAttention").replaceChildren();el("dxDashboardStatus").textContent="Unable to refresh. Try again.";}}finally{if(t===epoch)loading=false;}}
function access(ok){if(!ok){clear();return;}if(!active){active=true;el("dxDashboard").hidden=false;void refresh();}}
function bind(c){client=c;el("dxDashboardRefresh").addEventListener("click",refresh);root.addEventListener("dhaftar:notification-access",e=>access(e.detail===true));root.addEventListener("focus",()=>void refresh());access(root.DhaftarNotifications.hasAccess());}
root.DhaftarHome=Object.freeze({bind,money});
})(globalThis);
