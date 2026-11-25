/* Private, in-app reminder centre; source records remain authoritative. */
(function(root){
"use strict";
const labels={medication:"Medication",recurring:"Recurring payments",household:"Household bills",stock:"Stock",maintenance:"Maintenance"};
const links=new Set(["index.html#medicationUrgent","admin.html#recurringPersonalPanel","admin.html#billStatusSection","stock.html","amanah.html#personalAssetsPanel"]);
let client=null,user=null,feed=null,epoch=0,writing=false,filter="active",category="all",bell=null,container=null,notice=null;
const el=id=>document.getElementById(id);
const make=(tag,t,cls)=>{const n=document.createElement(tag);if(t!==undefined)n.textContent=String(t);if(cls)n.className=cls;return n;};
function visible(rows,mode,cat){return rows.filter(n=>(cat==="all"||n.category===cat)&&(mode==="snoozed"?n.snoozed:!n.snoozed&&(mode!=="unread"||!n.read_at)&&(mode!=="today"||["attention","overdue","today"].includes(n.urgency))));}
function urgency(n){return n.urgency==="overdue"?"Overdue":n.urgency==="today"?"Due today":n.urgency==="attention"?"Needs attention":"Upcoming";}
function setStatus(t){if(notice)notice.textContent=t;}
function access(value){root.dispatchEvent(new CustomEvent('dhaftar:notification-access',{detail:value}));}
function clear(){access(false);++epoch;user=null;feed=null;writing=false;if(bell)bell.hidden=true;if(container){container.replaceChildren();setStatus("Sign in to view your private reminders.");const a=make("a","Sign in","notice-button");a.href="admin.html";container.append(a);}for(const id of ["noticeUnread","noticeAttention","noticeTotal"])if(el(id))el(id).textContent="—";}
function count(){if(!bell)return;const n=Number(feed?.unread||0);bell.textContent="";bell.append(make("span","♧","notice-bell-glyph"));bell.firstChild.textContent="🔔";bell.append(make("span","Today"));if(feed&&n>0)bell.append(make("span",n>99?"99+":n,"notice-count"));bell.setAttribute("aria-label",feed?"Today, "+n+" unread reminders":"Open Today");}
function render(){
 if(!feed)return;count();if(!container)return;
 for(const [id,v] of [["noticeUnread",feed.unread],["noticeAttention",feed.attention],["noticeTotal",feed.notifications.filter(n=>!n.snoozed).length]])el(id).textContent=String(v);
 container.replaceChildren();const rows=visible(feed.notifications,filter,category);
 for(const n of rows){
  const card=make("article",undefined,"notice-card"+(!n.read_at?" notice-unread":""));
  const head=make("div",undefined,"notice-head");head.append(make("small",labels[n.category]||"Reminder"),make("span",n.snoozed?"Snoozed":urgency(n),"notice-urgency"));card.append(head,make("h2",n.title),make("p",n.detail));
  if(n.due_date)card.append(make("p","Due: "+n.due_date));
  if(n.snoozed)card.append(make("p","Snoozed until "+new Date(n.snoozed_until).toLocaleString("en-GB",{timeZone:"Indian/Maldives"})));
  const actions=make("div",undefined,"notice-actions");
  if(links.has(n.href)){const a=make("a","Open source","notice-button");a.href=n.href;if(n.category==="household"){const m=n.notification_key.match(/:(\d{4}-\d{2})-01$/);if(m)a.href="admin.html?noticeMonth="+m[1]+"#billStatusSection";}actions.append(a);}
  const button=(label,action,days)=>{const b=make("button",label,"notice-button");b.type="button";b.disabled=writing;b.addEventListener("click",()=>void act(n.notification_key,action,days));return b;};
  actions.append(button(n.read_at?"Mark unread":"Mark read",n.read_at?"unread":"read"));
  if(n.snoozed)actions.append(button("Unsnooze","unsnooze"));else{const select=make("select");select.setAttribute("aria-label","Snooze duration");for(const d of [1,3,7]){const o=make("option",d+" day"+(d===1?"":"s"));o.value=String(d);select.append(o);}const b=make("button","Snooze","notice-button");b.type="button";b.disabled=writing;b.addEventListener("click",()=>void act(n.notification_key,"snooze",Number(select.value)));actions.append(select,b);}
  card.append(actions);container.append(card);
 }
 if(!rows.length)container.append(make("p","No reminders in this view.","notice-empty"));
 setStatus("Updated for "+feed.today+" · Reminders resolve when their source is completed.");
}
async function refresh(){
 if(!client)return false;const token=++epoch;
 try{
  const session=await client.auth.getSession();if(token!==epoch)return false;
  const u=session.data?.session?.user?.id;if(session.error||!u){clear();return false;}
  if(user&&user!==u){feed=null;if(container)container.replaceChildren();}
  user=u;const r=await client.rpc("dhaftar_notifications_v6");if(token!==epoch||user!==u)return false;
  if(r.error)throw r.error;if(!r.data||!Array.isArray(r.data.notifications))throw Error("Invalid reminder response");
  feed=r.data;access(true);if(bell)bell.hidden=false;render();return true;
 }catch(e){if(token===epoch){feed=null;access(false);if(bell)bell.hidden=true;if(container){container.replaceChildren();for(const id of ["noticeUnread","noticeAttention","noticeTotal"])el(id).textContent="—";setStatus("Notifications unavailable. Sign in as administrator or refresh.");}}return false;}
}
async function act(key,action,days=null){
 if(writing||!user||!feed)return;writing=true;const u=user;render();
 try{const r=await client.rpc("dhaftar_notification_action_v6",{p_key:key,p_action:action,p_days:days});if(r.error)throw r.error;if(user===u)await refresh();}
 catch(e){if(user===u){await refresh();setStatus(e.message||"Unable to update reminder.");}}
 finally{writing=false;if(user===u&&feed){const message=notice?.textContent;render();if(message)setStatus(message);}}
}
function bind(c){
 if(client)return;client=c;container=el("noticeList");notice=el("noticeStatus");
 if(!container){bell=make("a",undefined,"dhaftar-notice-bell");bell.href="today.html";bell.hidden=true;document.body.append(bell);count();}
 else{el("noticeFilter").addEventListener("change",e=>{filter=e.target.value;render();});el("noticeCategory").addEventListener("change",e=>{category=e.target.value;render();});el("noticeRefresh").addEventListener("click",()=>void refresh());el("noticeReadAll").addEventListener("click",()=>void act(null,"read-all"));}
 client.auth.onAuthStateChange(event=>{if(event==="SIGNED_OUT"){clear();}else if(event==="SIGNED_IN"||event==="TOKEN_REFRESHED"){setTimeout(()=>void refresh(),0);}});
 root.addEventListener("focus",()=>void refresh());root.addEventListener("pageshow",()=>void refresh());document.addEventListener("visibilitychange",()=>{if(!document.hidden)void refresh();});
 // Only while the page is visible; no push/background monitoring.
 setInterval(()=>{if(!document.hidden&&!writing)void refresh();},60000);
 void refresh();
}
root.DhaftarNotifications=Object.freeze({bind,refresh,visible,urgency,hasAccess:()=>!!feed});
})(globalThis);
