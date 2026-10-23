import {expect,it} from 'vitest';
import routes from '../../public/_routes.json';
import {downloads} from './content';

it('every Android download endpoint reaches a Pages Function instead of the SPA fallback',()=>{
  const matches=(pattern:string,path:string)=>pattern.endsWith('*')?path.startsWith(pattern.slice(0,-1)):path===pattern;
  for(const url of [downloads.android.latestUrl,downloads.android.url,downloads.android.checksumUrl]){
    const path=new URL(url,'https://website.test').pathname;
    expect(routes.include.some(pattern=>matches(pattern,path))).toBe(true);
    expect(routes.exclude.some(pattern=>matches(pattern,path))).toBe(false);
  }
});
