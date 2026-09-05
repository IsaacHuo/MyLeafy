import { betterAuth } from 'better-auth';
import { authSchema } from './auth-schema';
import { ApiError } from './http';

export type Secrets = { AUTH_SECRET?:string; EMAIL_API_KEY?:string; EMAIL_FROM?:string; TEST_EMAIL_RECIPIENT?:string; LEGACY_SUPABASE_URL?:string; LEGACY_SUPABASE_PUBLISHABLE_KEY?:string; SCHOOL_VERIFIER_URL?:string; SCHOOL_VERIFIER_SECRET?:string; MEDIA_SIGNING_SECRET?:string };
export type BackendEnv=Env & Secrets;
export function auth(env:BackendEnv){
  if(!env.AUTH_SECRET||env.AUTH_SECRET.length<32)throw new ApiError(503,'auth_unavailable','Authentication is not configured');
  return betterAuth({
    ...authSchema(async(email,otp,type)=>{
      if(!env.EMAIL_API_KEY||!env.EMAIL_FROM)throw new ApiError(503,'email_unavailable','Email delivery is not configured');
      if(env.ENVIRONMENT==='staging'&&email!==env.TEST_EMAIL_RECIPIENT)throw new ApiError(403,'test_email_only','Staging only sends email to the configured test recipient');
      const response=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:`Bearer ${env.EMAIL_API_KEY}`,'Content-Type':'application/json'},body:JSON.stringify({from:env.EMAIL_FROM,to:[email],subject:type==='change-email'?'MyLeafy 绑定邮箱验证码':'MyLeafy 验证码',text:`你的 MyLeafy 验证码是 ${otp}。有效期 60 分钟。请勿向他人提供验证码。`}),signal:AbortSignal.timeout(15000)});
      if(!response.ok)throw new ApiError(502,'email_delivery_failed','Email delivery failed',true);
    }),
    database:env.DB,secret:env.AUTH_SECRET,baseURL:env.API_ORIGIN,trustedOrigins:[env.SITE_ORIGIN,env.API_ORIGIN,'leafy://'],
    advanced:{database:{generateId:'uuid'},ipAddress:{ipAddressHeaders:['cf-connecting-ip']}},
  });
}
export type Actor={authId:string;profileId:string;campusId:string|null;identityCampus:string;sessionId:string;sessionExpires:number};
export async function actor(env:BackendEnv,request:Request):Promise<Actor>{
  const session=await auth(env).api.getSession({headers:request.headers});
  if(!session)throw new ApiError(401,'unauthenticated','Please sign in');
  const link=await env.DB.prepare(`SELECT p.id AS profile_id,p.campus_id AS identity_campus,
    CASE WHEN p.campus_id='bjfu' THEN 'bjfu' ELSE p.community_campus_id END AS campus_id,
    p.community_access_status,c.status,c.is_community_enabled,u.banned_until
    FROM profile_auth_links l JOIN profiles p ON p.id=l.profile_id JOIN auth_users u ON u.id=l.auth_user_id
    LEFT JOIN campuses c ON c.id=CASE WHEN p.campus_id='bjfu' THEN 'bjfu' ELSE p.community_campus_id END
    WHERE l.auth_user_id=?`).bind(session.user.id).first<{profile_id:string;identity_campus:string;campus_id:string|null;community_access_status:string;status:string;is_community_enabled:number;banned_until:string|null}>();
  if(!link)throw new ApiError(403,'profile_required','Community profile is not linked');
  if(link.banned_until&&Date.parse(link.banned_until)>Date.now())throw new ApiError(403,'forbidden','Account is disabled');
  const enabled=link.status==='active'&&link.is_community_enabled===1&&(link.identity_campus==='bjfu'||link.community_access_status==='approved');
  return {authId:session.user.id,profileId:link.profile_id,identityCampus:link.identity_campus,campusId:enabled?link.campus_id:null,sessionId:session.session.id,sessionExpires:session.session.expiresAt.getTime()};
}
