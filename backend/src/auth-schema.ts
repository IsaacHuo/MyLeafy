import { anonymous, bearer, emailOTP } from 'better-auth/plugins';
import type { BetterAuthOptions } from 'better-auth';
import { compare, hash } from 'bcryptjs';

export function authSchema(send: (email:string,otp:string,type:string)=>Promise<void>) {
  return {
    basePath:'/v1/auth',
    user:{modelName:'identity_user',changeEmail:{enabled:false},deleteUser:{enabled:false}},
    session:{modelName:'identity_session',expiresIn:60*60*24*30,updateAge:60*60*24,cookieCache:{enabled:false}},
    account:{modelName:'identity_account',accountLinking:{enabled:false}},
    verification:{modelName:'identity_verification'},
    rateLimit:{enabled:true,storage:'database',modelName:'identity_rate_limit',window:60,max:30},
    advanced:{database:{generateId:'uuid'}},
    emailAndPassword:{enabled:true,minPasswordLength:8,maxPasswordLength:72,requireEmailVerification:true,
      password:{hash:(password:string)=>hash(password,12),verify:({hash:stored,password}:{hash:string;password:string})=>compare(password,stored)}},
    plugins:[anonymous({disableDeleteAnonymousUser:true}),bearer({requireSignature:true}),emailOTP({otpLength:8,expiresIn:3600,allowedAttempts:5,storeOTP:'hashed',overrideDefaultEmailVerification:true,changeEmail:{enabled:true,verifyCurrentEmail:false},sendVerificationOTP:({email,otp,type})=>send(email,otp,type)})],
  } satisfies BetterAuthOptions;
}
