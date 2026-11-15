// SkyNest M-Pesa Cloudflare Worker. Sandbox-first, one shortcode per deployment.
let darajaToken = null, darajaTokenExpiry = 0, googleToken = null, googleTokenExpiry = 0;
const reply = (data, status) => new Response(JSON.stringify(data), {status: status || 200, headers: {"content-type":"application/json","cache-control":"no-store","access-control-allow-origin":"*"}});
function b64url(input) { const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input; let s=""; for (const b of bytes) s+=String.fromCharCode(b); return btoa(s).replace(/=/g,"").replace(/\+/g,"-").replace(/\//g,"_"); }
function pemBytes(pem) { return Uint8Array.from(atob(pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g,"")), c=>c.charCodeAt(0)); }
async function googleAuth(env) {
  if (googleToken && Date.now()<googleTokenExpiry) return googleToken;
  const sa=JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON || "{}");
  if (!sa.client_email || !sa.private_key) throw Error("Firebase service account secret is missing.");
  const now=Math.floor(Date.now()/1000), aud=sa.token_uri || "https://oauth2.googleapis.com/token";
  const unsigned=b64url(JSON.stringify({alg:"RS256",typ:"JWT"}))+"."+b64url(JSON.stringify({iss:sa.client_email,scope:"https://www.googleapis.com/auth/datastore",aud,iat:now,exp:now+3600}));
  const key=await crypto.subtle.importKey("pkcs8",pemBytes(sa.private_key),{name:"RSASSA-PKCS1-v1_5",hash:"SHA-256"},false,["sign"]);
  const sig=await crypto.subtle.sign("RSASSA-PKCS1-v1_5",key,new TextEncoder().encode(unsigned));
  const r=await fetch(aud,{method:"POST",headers:{"content-type":"application/x-www-form-urlencoded"},body:new URLSearchParams({grant_type:"urn:ietf:params:oauth:grant-type:jwt-bearer",assertion:unsigned+"."+b64url(new Uint8Array(sig))})});
  const d=await r.json(); if(!r.ok||!d.access_token) throw Error("Firebase server authentication failed.");
  googleToken=d.access_token; googleTokenExpiry=Date.now()+Math.max(60,(d.expires_in||3600)-120)*1000; return googleToken;
}
function enc(v) { if(v===null||v===undefined)return {nullValue:null}; if(typeof v==="string")return {stringValue:v}; if(typeof v==="boolean")return {booleanValue:v}; if(Number.isInteger(v))return {integerValue:String(v)}; if(typeof v==="number")return {doubleValue:v}; return {stringValue:String(v)}; }
function encFields(o) { const f={}; for(const k in o) f[k]=enc(o[k]); return f; }
function decFields(f) { const o={}; for(const k in (f||{})){const v=f[k]; if(v.stringValue!==undefined)o[k]=v.stringValue; else if(v.integerValue!==undefined)o[k]=Number(v.integerValue); else if(v.doubleValue!==undefined)o[k]=v.doubleValue; else if(v.booleanValue!==undefined)o[k]=v.booleanValue; else if(v.timestampValue!==undefined)o[k]=v.timestampValue;} return o; }
async function fs(env,path,init) {
  const token=await googleAuth(env), url="https://firestore.googleapis.com/v1/projects/"+env.FIREBASE_PROJECT_ID+"/databases/(default)/documents/"+path;
  const r=await fetch(url,{...init,headers:{authorization:"Bearer "+token,"content-type":"application/json",...(init&&init.headers||{})}});
  const d=await r.json().catch(()=>({})); if(!r.ok&&r.status!==404)throw Error((d.error&&d.error.message)||"Firestore request failed."); return {status:r.status,data:d};
}
async function userIdFrom(request,env) {
  const h=request.headers.get("authorization")||"", idToken=h.startsWith("Bearer ")?h.slice(7):"";
  if(!idToken)throw Error("Sign in to SkyNest first.");
  const r=await fetch("https://identitytoolkit.googleapis.com/v1/accounts:lookup?key="+env.FIREBASE_WEB_API_KEY,{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({idToken})});
  const d=await r.json(), u=d.users&&d.users[0]; if(!r.ok||!u||u.disabled)throw Error("SkyNest session is invalid. Sign in again."); return u.localId;
}
async function authToken(env) {
  if(darajaToken&&Date.now()<darajaTokenExpiry)return darajaToken;
  const root=env.DARAJA_ENV==="production"?"https://api.safaricom.co.ke":"https://sandbox.safaricom.co.ke";
  const basic=btoa(env.DARAJA_CONSUMER_KEY+":"+env.DARAJA_CONSUMER_SECRET);
  const r=await fetch(root+"/oauth/v1/generate?grant_type=client_credentials",{headers:{authorization:"Basic "+basic}});
  const d=await r.json(); if(!r.ok||!d.access_token)throw Error("Daraja authentication failed; check Worker secrets.");
  darajaToken=d.access_token; darajaTokenExpiry=Date.now()+Math.max(60,Number(d.expires_in||3600)-120)*1000; return darajaToken;
}
function phoneNumber(v) { let p=String(v||"").replace(/[\s+()-]/g,""); if(p.startsWith("0"))p="254"+p.slice(1); if(p.startsWith("7")||p.startsWith("1"))p="254"+p; if(!/^254[17]\d{8}$/.test(p))throw Error("Enter a valid Kenyan M-Pesa phone number."); return p; }
function timestamp() { const d=new Date(Date.now()+3*3600000); return d.getUTCFullYear()+String(d.getUTCMonth()+1).padStart(2,"0")+String(d.getUTCDate()).padStart(2,"0")+String(d.getUTCHours()).padStart(2,"0")+String(d.getUTCMinutes()).padStart(2,"0")+String(d.getUTCSeconds()).padStart(2,"0"); }
async function stk(request,env) {
  const uid=await userIdFrom(request,env), input=await request.json(), amount=Math.floor(Number(input.amountKes)), phone=phoneNumber(input.phone);
  if(!Number.isSafeInteger(amount)||amount<1||amount>150000)throw Error("Amount must be between KES 1 and 150,000.");
  const profile=await fs(env,"users/"+uid); if(profile.status===404)throw Error("Tenant profile not found.");
  const p=decFields(profile.data.fields); if(p.role!=="tenant"||p.status!=="active"||!p.landlordId)throw Error("Only an active tenant linked to a landlord can pay rent.");
  if(!env.DARAJA_SHORTCODE||!env.DARAJA_PASSKEY)throw Error("Daraja shortcode/passkey not configured.");
  const root=env.DARAJA_ENV==="production"?"https://api.safaricom.co.ke":"https://sandbox.safaricom.co.ke", time=timestamp();
  const callback=env.STK_CALLBACK_URL; if(!callback||!callback.startsWith("https://"))throw Error("Configure public HTTPS STK_CALLBACK_URL.");
  const token=await authToken(env), reference="SN"+crypto.randomUUID().replace(/-/g,"").slice(0,10).toUpperCase();
  const payload={BusinessShortCode:env.DARAJA_SHORTCODE,Password:btoa(env.DARAJA_SHORTCODE+env.DARAJA_PASSKEY+time),Timestamp:time,TransactionType:"CustomerPayBillOnline",Amount:amount,PartyA:phone,PartyB:env.DARAJA_SHORTCODE,PhoneNumber:phone,CallBackURL:callback,AccountReference:reference,TransactionDesc:"SkyNest rent"};
  const r=await fetch(root+"/mpesa/stkpush/v1/processrequest",{method:"POST",headers:{authorization:"Bearer "+token,"content-type":"application/json"},body:JSON.stringify(payload)});
  const d=await r.json(); if(!r.ok||d.ResponseCode!=="0"||!d.CheckoutRequestID)throw Error(d.errorMessage||d.ResponseDescription||"Safaricom rejected STK Push.");
  await fs(env,"mpesaPaymentRequests?documentId="+encodeURIComponent(d.CheckoutRequestID),{method:"POST",body:JSON.stringify({fields:encFields({checkoutRequestId:d.CheckoutRequestID,merchantRequestId:d.MerchantRequestID||"",tenantId:uid,landlordId:p.landlordId,houseId:p.houseId||"",houseNo:p.houseNo||"",amountKes:amount,phone,accountReference:reference,status:"pending",createdAt:new Date().toISOString()})})});
  return reply({accepted:true,message:d.CustomerMessage||"Check your phone and enter your M-Pesa PIN.",checkoutRequestId:d.CheckoutRequestID});
}
async function stkResult(request,env) {
  const body=await request.json(), cb=body.Body&&body.Body.stkCallback; if(!cb||!cb.CheckoutRequestID)return reply({ResultCode:0,ResultDesc:"Accepted"});
  const id=cb.CheckoutRequestID, found=await fs(env,"mpesaPaymentRequests/"+encodeURIComponent(id));
  if(found.status===404)return reply({ResultCode:0,ResultDesc:"Accepted"});
  const pending=decFields(found.data.fields); if(["confirmed","failed"].includes(pending.status))return reply({ResultCode:0,ResultDesc:"Duplicate ignored"});
  const success=Number(cb.ResultCode)===0, meta={}; for(const item of ((cb.CallbackMetadata&&cb.CallbackMetadata.Item)||[]))meta[item.Name]=item.Value;
  if(success) {
    const receipt=String(meta.MpesaReceiptNumber||""); if(!receipt)throw Error("Missing M-Pesa receipt on successful callback.");
    await fs(env,"payments?documentId="+encodeURIComponent(receipt),{method:"POST",body:JSON.stringify({fields:encFields({tenantId:pending.tenantId,landlordId:pending.landlordId,createdBy:pending.landlordId,houseId:pending.houseId,houseNo:pending.houseNo,amount:Number(meta.Amount||pending.amountKes),method:"MPESA",transactionCode:receipt,mpesaReceipt:receipt,status:"Paid",confirmedBy:"safaricom_callback",checkoutRequestId:id,phone:String(meta.PhoneNumber||pending.phone),createdAt:new Date().toISOString(),confirmedAt:new Date().toISOString()})})});
  }
  await fs(env,"mpesaPaymentRequests/"+encodeURIComponent(id),{method:"PATCH",body:JSON.stringify({fields:encFields({...pending,status:success?"confirmed":"failed",resultCode:Number(cb.ResultCode),resultDescription:cb.ResultDesc||"",mpesaReceipt:String(meta.MpesaReceiptNumber||""),updatedAt:new Date().toISOString()})})});
  return reply({ResultCode:0,ResultDesc:"Accepted"});
}
export default { async fetch(request,env) {
  if(request.method==="OPTIONS")return new Response(null,{headers:{"access-control-allow-origin":"*","access-control-allow-methods":"GET,POST,OPTIONS","access-control-allow-headers":"authorization,content-type"}});
  const path=new URL(request.url).pathname;
  try {
    if(request.method==="GET"&&path==="/health")return reply({ok:true,service:"skynest-mpesa",environment:env.DARAJA_ENV||"sandbox"});
    if(request.method==="POST"&&path==="/api/mpesa/stkpush")return await stk(request,env);
    if(request.method==="POST"&&path==="/hooks/stk/result/"+env.STK_CALLBACK_TOKEN)return await stkResult(request,env);
    return reply({error:"Not found"},404);
  } catch(e) { return reply({error:e.message||"Payment service error"},400); }
}};
