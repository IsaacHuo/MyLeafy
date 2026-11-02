import {beforeEach,describe,it,expect} from 'vitest';
import {refineAccess} from './refine';
import {saveIdentity} from './session';

describe('Refine permission bridge',()=>{
  beforeEach(()=>{
    localStorage.clear();sessionStorage.clear();
    saveIdentity({admin:{id:'viewer',username:'viewer',display_name:'只读',role:'viewer',active:true},permissions:[{resource:'posts',actions:['list','show']}],session:{expires_at:'2099-01-01T00:00:00Z'}});
  });
  it('does not convert bulk/export or unrecognised actions to ordinary list access',async()=>{
    await expect(refineAccess.can({resource:'posts',action:'list'})).resolves.toMatchObject({can:true});
    for(const action of ['export','bulk','edit','delete','create','clone'])await expect(refineAccess.can({resource:'posts',action})).resolves.toMatchObject({can:false});
    await expect(refineAccess.can({resource:'monitoring',action:'list'})).resolves.toMatchObject({can:false});
  });
});
