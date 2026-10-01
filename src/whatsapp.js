import makeWASocket, {initAuthCreds,BufferJSON,proto,DisconnectReason} from '@whiskeysockets/baileys';
import pino from 'pino';
import QRCode from 'qrcode';
export function gateway(store, encryption, emit) {
 const sockets=new Map(), qrs=new Map(), reconnects=new Map(), connecting=new Set(), stopped=new Set();
 const logger=pino({level:'silent'});
 async function connect(instance) {
  if(sockets.has(instance.id)||connecting.has(instance.id))return;
  connecting.add(instance.id); stopped.delete(instance.id);
  try {
   const read=async k=>{const r=await store.get('auth:'+instance.id,k);return r?JSON.parse(encryption.open(r.data),BufferJSON.reviver):null;};
   const write=async(k,v)=>store.set('auth:'+instance.id,k,{data:encryption.seal(JSON.stringify(v,BufferJSON.replacer))});
   const creds=await read('creds')||initAuthCreds();
   const socket=makeWASocket({logger,auth:{creds,keys:{async get(type,ids){const result={}; for(const id of ids){let v=await read(type+'-'+id);if(type==='app-state-sync-key'&&v)v=proto.Message.AppStateSyncKeyData.fromObject(v);result[id]=v;}return result;},async set(data){for(const type in data)for(const id in data[type]){const key=type+'-'+id; if(data[type][id])await write(key,data[type][id]);else await store.delete('auth:'+instance.id,key);}}}},getMessage:async key=>{const row=await store.get('wa-message:'+instance.id,key.id);return row?JSON.parse(encryption.open(row.data),BufferJSON.reviver):undefined;},markOnlineOnConnect:false,syncFullHistory:false});
   sockets.set(instance.id,socket);
   socket.ev.on('creds.update',()=>write('creds',creds).catch(()=>emit(instance,'error',{message:'Session persistence failed'})));
   socket.ev.on('connection.update',async update=>{
    try {
     if(update.qr){qrs.set(instance.id,await QRCode.toDataURL(update.qr));instance.status='awaiting_qr';}
     if(update.connection==='open'){instance.status='connected';instance.phone=socket.user?.id?.split(':')[0];qrs.delete(instance.id);reconnects.set(instance.id,0);}
     if(update.connection==='close'){sockets.delete(instance.id);qrs.delete(instance.id);const code=update.lastDisconnect?.error?.output?.statusCode;const terminal=[DisconnectReason.loggedOut,DisconnectReason.badSession,DisconnectReason.connectionReplaced,DisconnectReason.forbidden].includes(code);instance.status=terminal?'disconnected':'reconnecting';if(!terminal&&!stopped.has(instance.id)){const n=(reconnects.get(instance.id)||0)+1;reconnects.set(instance.id,n);if(n<=8)setTimeout(()=>connect(instance).catch(()=>{}),Math.min(30000,1000*2**n)).unref();else instance.status='disconnected';}}
     const current=await store.get('instances',instance.id);if(current){instance={...current,status:instance.status,phone:instance.phone};await store.set('instances',instance.id,instance);}await emit(instance,'connection',{status:instance.status});
    }catch {logger.error('Connection persistence failed');}
   });
   socket.ev.on('messages.upsert',async ({messages,type})=>{for(const m of messages){if(!m.message||!m.key.id)continue;try{await store.set('wa-message:'+instance.id,m.key.id,{data:encryption.seal(JSON.stringify(m.message,BufferJSON.replacer))}); await emit(instance,'message',{id:m.key.id,chatId:m.key.remoteJid,fromMe:m.key.fromMe,type,text:m.message.conversation||m.message.extendedTextMessage?.text||'',message:m.message});}catch {logger.error('Message persistence failed');}}});
   socket.ev.on('messages.update',async updates=>{try{await emit(instance,'receipt',{updates});}catch {}});
  }finally{connecting.delete(instance.id);}
 }
 const active=id=>{const s=sockets.get(id);if(!s?.user)throw Object.assign(Error('Connect this WhatsApp instance first'),{status:409});return s;};
 return {connect,qr:id=>qrs.get(id),active,async disconnect(instance,logout=false){stopped.add(instance.id);const s=sockets.get(instance.id);if(s){if(logout)await s.logout();else s.end(undefined);}sockets.delete(instance.id);qrs.delete(instance.id);instance.status='disconnected';await store.set('instances',instance.id,instance);},async shutdown(){for(const id of sockets.keys())stopped.add(id);for(const s of sockets.values())s.end(undefined);sockets.clear();}};
}
