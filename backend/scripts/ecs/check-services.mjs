// Read-only provider connectivity. Never sends an email or dispatches a release.
const result={checkedAt:new Date().toISOString(),environment:process.env.ENVIRONMENT};
try{
 const response=await fetch('https://api.resend.com/domains',{headers:{Authorization:`Bearer ${process.env.EMAIL_API_KEY??''}`},signal:AbortSignal.timeout(15000)});
 result.emailProviderHTTP=response.status;
 if(response.ok){
  const body=await response.json(),sender=process.env.EMAIL_FROM?.match(/@([^>\s]+)/)?.[1];
  const domain=body.data?.find(d=>d.name===sender);
  result.configuredSenderDomain=sender??null;result.senderVerified=domain?.status==='verified';
 }
}catch{result.emailProviderReachable=false;}
try{
 const response=await fetch('https://api.github.com/repos/IsaacHuo/MyLeafy/actions/workflows/android-release.yml',{headers:{'User-Agent':'MyLeafy-ECS-acceptance',...(process.env.GITHUB_RELEASE_TOKEN?{Authorization:`Bearer ${process.env.GITHUB_RELEASE_TOKEN}`}:{})},signal:AbortSignal.timeout(15000)});
 result.githubHTTP=response.status;result.githubCredentialConfigured=!!process.env.GITHUB_RELEASE_TOKEN;
}catch{result.githubReachable=false;}
console.log(JSON.stringify(result));
